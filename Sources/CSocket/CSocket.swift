//
//  CSocket.swift
//  CMDLine
//
//  Created by Adhiraj Singh on 7/20/18.
//  Copyright © 2018 Adhiraj Singh. All rights reserved.
//
//  Pure Swift TCP Socket based on ytcpsocket.c & BlueSocket
//  Uses C Non blocking sockets but made blocking using swift
#if os(Linux)
import Glibc
#else
import Darwin
#endif

import Foundation


public class CSocket {
    
    public enum Error: Swift.Error {
        case failedToObtainIPAddress
        case alreadyConnected
        case error (Int32, String)
        
        static func currentError () -> Error {
            return error(errno)
        }
        static func error (_ err: Int32) -> Error {
            let str = String(cString: strerror(err) )
            return .error(err, str)
        }
        static  func socketNotOpenError () -> Error {
            return .error(150, "Socket Not Open")
        }
        static func timedOutError () -> Error {
            return .error(110, "Connection Timed Out")
        }
    }
    
    public static var connectCheckIntervalMS = 100
    public static var sendIntervalMS = 20
    public static var readIntervalMS = 50
    
    public static let defaultHost = "::/0"
    
    static let inet_protocol: Int32 = AF_INET6
    
    public let address: String
    public let port: Int32
    
    public var isConnected: Bool {
        return fd.get() != nil
    }
    
    public var description: String {
        return "\(address):\(port) \( fd.get()?.description ?? "" )"
    }
    
    public var connectTimeout = 5.0
    public var sendTimeout = 5.0
    public var readTimeout = 5.0
    
    public var delegate: SocketAsyncOperationsDelegate?
    
    let fd = AtomicValue<Int32?>(nil)
    
    
    
    let queue = DispatchQueue(label: "socket", qos: .default, attributes: [], autoreleaseFrequency: .inherit, target: nil)
    
    var dispatchSource: DispatchSourceProtocol?
    
    let sendSM = DispatchSemaphore(value: 1)
    
    var sendTmpData = [UInt8]()
    var sendTmpBytesSent = 0
    var sendStartDate = Date(timeIntervalSince1970: 0)
    var sendSyncCall = false
    
    var sendErr: CSocket.Error?
    
    let readSM = DispatchSemaphore(value: 1)
    
    var tmpData = [UInt8]()
    var tmpBytesRead = 0
    var readStartDate = Date(timeIntervalSince1970: 0)
    var readSyncCall = false
    
    var readErr: CSocket.Error?
    
    public init(address: String, port: Int32, inet_protocol: Int32) {
        
        self.address = inet_protocol == AF_INET ? "::ffff:\(address)" : address
        self.port = port
        
    }
    public init (host: String, port: Int32) throws {
        
        var inet_protocol: Int32 = 0
        let addr = try CSocket.getHostIP(host, prot: &inet_protocol)
        
        self.address = inet_protocol == AF_INET ? "::ffff:\(addr)" : addr
        self.port = port
    }
    public init (port: Int32) {
        self.address = CSocket.defaultHost
        self.port = port
    }
    
    func syncOperation (asyncTask: (() -> Void), sm: DispatchSemaphore, error: inout CSocket.Error?, syncSwitch: inout Bool) throws {
        
        sm.wait()
        
        syncSwitch = true
        
        asyncTask()
        sm.wait()
        
        syncSwitch = false
        
        sm.signal()
        
        if let error = error {
            throw error
        }
        
    }
    
    public func availableData () -> Int {
        guard let socketfd = fd.get() else {
            return 0
        }
        
        var count: CInt = 0
        _ = ioctl(CInt(socketfd), UInt(FIONREAD), &count)
        return Int(count)
    }
    
    public static func getHostIP(_ host: String, prot: inout Int32) throws -> String {
        
        var pointer: UnsafeMutablePointer<addrinfo>?
        
        let r = getaddrinfo(host, nil, nil, &pointer)
        
        if r < 0 {
            throw CSocket.Error.currentError()
        }
        
        var cli_addr = pointer!.pointee.ai_addr.pointee
        
        prot = Int32(cli_addr.sa_family)
        
        let str: String
        if cli_addr.sa_family == AF_INET6 {
            
            var in_addr = sockaddr_in6.init()
            memcpy(&in_addr, &cli_addr, Int( MemoryLayout.size(ofValue: cli_addr) ))
            
            var ip = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if inet_ntop(AF_INET6, &in_addr.sin6_addr, &ip, socklen_t(INET6_ADDRSTRLEN)) == nil {
                throw CSocket.Error.failedToObtainIPAddress
            }
            
            str = String(cString: ip)
            
        } else {
            var in_addr = sockaddr_in.init()
            memcpy(&in_addr, &cli_addr, Int( MemoryLayout.size(ofValue: cli_addr) ))
            
            var ip = [Int8](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &in_addr.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN)) == nil {
                throw CSocket.Error.failedToObtainIPAddress
            }
            
            str = String(cString: ip)
        }
        
        return str
    }
    
    static func porthtons(_ port: in_port_t) -> in_port_t {
        #if os(Linux)
        return htons(port)
        #else
        let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
        return isLittleEndian ? _OSSwapInt16(port) : port
        #endif
    }
    
    static func makeNonBlocking (socket: Int32) {
        let flags = fcntl(socket, F_GETFL, 0)
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
    }
    
}
extension CSocket: Hashable {
    
    public static func == (lhs: CSocket, rhs: CSocket) -> Bool {
        return lhs.address == rhs.address && lhs.port == rhs.port
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(address)
        hasher.combine(port)
    }
}

// C replacement Utils -------------------------------------



#if os(Linux)
//private let FIONREAD = Glibc.FIONREAD
let sockStreamType = Int32(SOCK_STREAM.rawValue)
#else
let sockStreamType = SOCK_STREAM
let FIONREAD : CUnsignedLong = CUnsignedLong( IOC_OUT ) | ((CUnsignedLong(4 /* Int32 */) & CUnsignedLong(IOCPARM_MASK)) << 16) | (102 /* 'f' */ << 8) | 127
#endif


#if os(Linux)

#if arch(arm)
let __fd_set_count = 16
#else
let __fd_set_count = 32
#endif

extension fd_set {
    
    @inline(__always)
    mutating func withCArrayAccess<T>(block: (UnsafeMutablePointer<Int32>) throws -> T) rethrows -> T {
        return try withUnsafeMutablePointer(to: &__fds_bits) {
            try block(UnsafeMutableRawPointer($0).assumingMemoryBound(to: Int32.self))
        }
    }
}

#else   // not Linux on ARM

// __DARWIN_FD_SETSIZE is number of *bits*, so divide by number bits in each element to get element count
// at present this is 1024 / 32 == 32
let __fd_set_count = Int(__DARWIN_FD_SETSIZE) / 32

public extension fd_set {
    
    @inline(__always)
    mutating func withCArrayAccess<T>(block: (UnsafeMutablePointer<Int32>) throws -> T) rethrows -> T {
        return try withUnsafeMutablePointer(to: &fds_bits) {
            try block(UnsafeMutableRawPointer($0).assumingMemoryBound(to: Int32.self))
        }
    }
}

#endif

public extension fd_set {
    
    @inline(__always)
    private static func address(for fd: Int32) -> (Int, Int32) {
        var intOffset = Int(fd) / __fd_set_count
        #if _endian(big)
        if intOffset % 2 == 0 {
            intOffset += 1
        } else {
            intOffset -= 1
        }
        #endif
        let bitOffset = Int(fd) % __fd_set_count
        let mask = Int32(bitPattern: UInt32(1 << bitOffset))
        return (intOffset, mask)
    }
    
    ///
    /// Zero the fd_set
    ///
    mutating func zero() {
        #if swift(>=4.1)
        withCArrayAccess { $0.initialize(repeating: 0, count: __fd_set_count) }
        #else
        withCArrayAccess { $0.initialize(to: 0, count: __fd_set_count) }
        #endif
    }
    
    ///
    /// Set an fd in an fd_set
    ///
    /// - Parameter fd:    The fd to add to the fd_set
    ///
    mutating func set(_ fd: Int32) {
        let (index, mask) = fd_set.address(for: fd)
        withCArrayAccess { $0[index] |= mask }
    }
    
    ///
    /// Clear an fd from an fd_set
    ///
    /// - Parameter fd:    The fd to clear from the fd_set
    ///
    mutating func clear(_ fd: Int32) {
        let (index, mask) = fd_set.address(for: fd)
        withCArrayAccess { $0[index] &= ~mask }
    }
    
    ///
    /// Check if an fd is present in an fd_set
    ///
    /// - Parameter fd:    The fd to check
    ///
    ///    - Returns:    True if present, false otherwise.
    ///
    mutating func isSet(_ fd: Int32) -> Bool {
        let (index, mask) = fd_set.address(for: fd)
        return withCArrayAccess { $0[index] & mask != 0 }
    }
}


