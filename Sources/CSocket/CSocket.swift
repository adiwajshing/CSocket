//
//  CSocket.swift
//  CMDLine
//
//  Created by Adhiraj Singh on 7/20/18.
//  Copyright © 2018 Adhiraj Singh. All rights reserved.
//

#if os(Linux)
import Glibc
#else
import Darwin
#endif

import Foundation

///Pure Swift TCP Socket
open class CSocket: CustomStringConvertible {
    
    /// Swift wrapper around C AF_INET6 & AF_INET
    public enum INETProtocol {
        case ipv6
        case ipv4
        
        init (_ rawValue: Int32) {
            switch rawValue {
            case AF_INET6:
                self = .ipv6
            default:
                self = .ipv4
            }
        }
        
        public var rawValue: Int32 {
            return self == .ipv6 ? AF_INET6 : AF_INET
        }
    }
    
    /// Swifr wrapper around the C errno
    public enum Error: Swift.Error {
        case failedToObtainIPAddress
        case alreadyConnected
        case error (Int32, String)
        
        init (_ err: Int32) {
            let str = String(cString: strerror(err) )
            self = .error(err, str)
        }
        
        static func current () -> Error {
            return Error(errno)
        }
        static  func socketNotOpenError () -> Error {
            return .error(150, "Socket Not Open")
        }
        static func timedOutError () -> Error {
            return .error(110, "Connection Timed Out")
        }
    }
    
    ///the dispatch queue which takes takes care of all async operations of all CSockets
    public static var updateQueue = DispatchQueue(label: "c_socket_queue", qos: .default, attributes: [.concurrent], autoreleaseFrequency: .inherit, target: nil)
    
    ///the interval between checks for whether the socket has connected
    public static var connectCheckIntervalMS = 100
    ///the interval between c send calls
    public static var sendIntervalMS = 20
    ///the interval between each c recv calls
    public static var readIntervalMS = 50
    
    ///the host at which a listener is started
    public static let defaultHost = "::/0"
    
    static let inetProtocol = INETProtocol.ipv6.rawValue
    
    
    public let address: String
    public let port: Int32
    
    ///returns whether the socket is connected; whether the socketfd is set or not
    public var isConnected: Bool {
        return fd.get() != nil
    }
    
    public var description: String {
        return "\(address):\(port) \( fd.get()?.description ?? "" )"
    }
    
    ///max timeout for connecting (for both async & sync operations)
    public var connectTimeout = 5.0
    ///max timeout for sending data (for both async & sync operations)
    public var sendTimeout = 5.0
    ///max timeout for reading data (for both async & sync operations)
    public var readTimeout = 5.0
    ///the minimum number of bytes required for the dataDidBecomeAvailable (socket:, bytes:) callback to be called
    public var readBytesThreshhold = 0
    
    ///the delegate which is called for all async operations
    public var delegate: CSocketAsyncOperationsDelegate?
    
    ///the file descriptor for the socket; C uses these integers to reference connections
    ///It is an AtomicValue to ensure thread safety
    let fd = AtomicValue<Int32?>(nil)
    
    ///the source used for the accepting loop & read loop
    var dispatchSource: DispatchSourceProtocol?
    
    ///DispatchSemaphore that ensures only one send operation happens at any given time
    let sendSM = DispatchSemaphore(value: 1)
    
    var sendTmpData = Data()
    var sendTmpBytesSent = 0
    var sendStartDate = Date(timeIntervalSince1970: 0)
    
    var sendErr: CSocket.Error?
    
    ///DispatchSemaphore that ensures only one read operation happens at any given time
    let readSM = DispatchSemaphore(value: 1)
    
    var tmpData = Data()
    var tmpBytesRead = 0
    var readStartDate = Date(timeIntervalSince1970: 0)
    
    var readErr: CSocket.Error?
    
    ///Create a socket specifying an address, port & the address type (ipv4, ipv6). DO NOT USE FOR DOMAINS (eg. www.google.com), USE CSocket.init(host:, port:) FOR THOSE.
    public init(address: String, port: Int32, addressType: CSocket.INETProtocol) {
        self.address = addressType == .ipv4 ? "::ffff:\(address)" : address
        self.port = port
    }
    
    ///Create a socket specifying a host & port. Parses domains automatically
    public init (host: String, port: Int32) throws {
        
        var p: INETProtocol = .ipv6
        let addr = try CSocket.getHostIP(host, prot: &p) //parse the domain
        
        self.address = p == .ipv4 ? "::ffff:\(addr)" : addr //if the IP Address is IPV4, wrap it as an IPV6 address
        self.port = port
    }
    
    ///Creates a socket for listening, just specify a port to listen on
    public init (port: Int32) {
        self.address = CSocket.defaultHost
        self.port = port
    }
    
    ///Returns the number of bytes available to be read
    public func availableData () -> Int {
        guard let socketfd = fd.get() else {
            return 0
        }
        
        var count: CInt = 0
        _ = ioctl(CInt(socketfd), UInt(FIONREAD), &count)
        return Int(count)
    }
    
    ///Returns the IP Address of a domain along with its INETProtocol (ipv4 or ipv6)
    public static func getHostIP(_ host: String, prot: inout CSocket.INETProtocol) throws -> String {
        
        var pointer: UnsafeMutablePointer<addrinfo>?
        
        let r = getaddrinfo(host, nil, nil, &pointer)
        
        if r < 0 {
            throw CSocket.Error.current()
        }
        
        var cli_addr = pointer!.pointee.ai_addr.pointee
        
        prot = INETProtocol(Int32(cli_addr.sa_family))
        
        var ip: [Int8]
        if prot == INETProtocol.ipv6 {
            
            var in_addr = sockaddr_in6.init()
            memcpy(&in_addr, &cli_addr, Int( MemoryLayout.size(ofValue: cli_addr) ))
            
            ip = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if inet_ntop(AF_INET6, &in_addr.sin6_addr, &ip, socklen_t(INET6_ADDRSTRLEN)) == nil {
                throw CSocket.Error.failedToObtainIPAddress
            }
            
        } else {
            var in_addr = sockaddr_in.init()
            memcpy(&in_addr, &cli_addr, Int( MemoryLayout.size(ofValue: cli_addr) ))
            
            ip = [Int8](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &in_addr.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN)) == nil {
                throw CSocket.Error.failedToObtainIPAddress
            }

        }
        
        return String(cString: ip)
    }
    
    ///make the port BigEndian encoding (network encoding)
    static func porthtons(_ port: in_port_t) -> in_port_t {
        #if os(Linux)
        return htons(port)
        #else
        let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
        return isLittleEndian ? _OSSwapInt16(port) : port
        #endif
    }
    
    ///make the socket non blocking
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

// C replacement Utils (from BlueSocket) -------------------------------------

#if os(Linux)
//private let FIONREAD = Glibc.FIONREAD
let sockStreamType = Int32(SOCK_STREAM.rawValue)
#else
let sockStreamType = SOCK_STREAM
let FIONREAD : CUnsignedLong =
    CUnsignedLong( IOC_OUT ) |
    ((CUnsignedLong(4) & CUnsignedLong(IOCPARM_MASK)) << 16) |
        (102 << 8) | 127
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

#else

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


