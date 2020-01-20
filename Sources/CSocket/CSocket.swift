//
//  CSocket.swift
//  CMDLine
//
//  Created by Adhiraj Singh on 7/20/18.
//  Copyright © 2018 Adhiraj Singh. All rights reserved.
//  Add breakpoint with command on macOS: process handle SIGPIPE -n false -p false -s false

#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Atomics
import Promises
import Foundation

///Pure Swift TCP Socket
open class CSocket: CustomStringConvertible {
    ///the host at which a listener is started
    public static let defaultHost = "::/0"
    
    static let inetProtocol = INETProtocol.ipv6.rawValue
    
    public let address: String
    public let port: Int32
    
    ///returns whether the socket is connected; whether the socketfd is set or not
    open var isConnected: Bool { fd.syncPointee != nil }
    
    open var description: String { "\(address):\(port) \( fd.syncPointee?.description ?? "" )" }
    ///the dispatch queue on which all socket operations are executed on
    public let queue = DispatchQueue(label: "socket_queue", attributes: [])
    
    var dispatchSource: DispatchSourceProtocol?

    ///the file descriptor for the socket; They're used in C to reference connections
    ///It is an atomic value to ensure thread safety
    let fd = AtomicMutablePointer<Int32?>(nil)
    
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
    
    ///Copy the socket information into a new instance
    public init <T: CSocket> (_ socket: T) {
        self.address = socket.address
        self.port = socket.port
        self.fd.syncPointee = socket.fd.syncPointee
    }
    
    ///Returns the number of bytes available to be read
    public func availableData () -> Int {
        guard let socketfd = fd.syncPointee else { return 0 }
        
        var count: CInt = 0
        _ = ioctl(CInt(socketfd), UInt(FIONREAD), &count)
        return Int(count)
    }
    
    internal func timerForTimeout <T> (timeout: DispatchTimeInterval, source: DispatchSourceProtocol, promise: Promise<T>) -> DispatchSourceTimer? {
        
        if timeout == .never { return nil }
        
        let timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            timer.cancel()
            source.cancel()
            promise.reject(CSocket.Error.timedOut)
            self.close() // close the socket
        }
        return timer
    }
    //deinit { print("socket deinit") }
}
extension CSocket: Hashable {
    
    public static func == (lhs: CSocket, rhs: CSocket) -> Bool {
        lhs.address == rhs.address && lhs.port == rhs.port
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(address)
        hasher.combine(port)
    }
}
