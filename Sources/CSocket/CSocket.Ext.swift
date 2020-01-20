//
//  File.swift
//  
//
//  Created by Adhiraj Singh on 1/17/20.
//

import Foundation

public extension CSocket {
    
    /// Swift wrapper around C AF_INET6 & AF_INET
    enum INETProtocol {
        case ipv6
        case ipv4
        
        public init (rawValue: Int32) {
            switch rawValue {
            case AF_INET6:
                self = .ipv6
                break
            default:
                self = .ipv4
                break
            }
        }
        
        public var rawValue: Int32 { self == .ipv6 ? AF_INET6 : AF_INET }
    }
    
    /// Swifr wrapper around the C errno
    enum Error: Swift.Error, CustomStringConvertible {
        case failedToObtainIPAddress
        case error (Int32, String)
        
        init (_ err: Int32) { self = .error(err, String(cString: strerror(err))) }
        
        public var description: String {
            switch self {
            case .error(let code, let str):
                return "CSocket.Error(\(code), \(str))"
            case .failedToObtainIPAddress:
                return "CSocket.Error(Failed to obtain IP address)"
            }
        }
        
        static var alreadyConnected: Error { .init(EISCONN) }
        static var socketNotOpen: Error { .init(ENOTCONN) }
        static var timedOut: Error { .error(ETIMEDOUT, "Connection Timed Out") }
        
        static func current () -> Error { Error(errno) }
    }
    
    ///Returns the IP Address of a domain along with its INETProtocol (ipv4 or ipv6)
    static func getHostIP(_ host: String, prot: inout CSocket.INETProtocol) throws -> String {
        
        var pointer: UnsafeMutablePointer<addrinfo>!
        
        let r = getaddrinfo(host, nil, nil, &pointer)
        
        if r < 0 { throw CSocket.Error.current() }
        
        var cli_addr = pointer.pointee.ai_addr.pointee
        
        prot = INETProtocol(rawValue: Int32(cli_addr.sa_family))
        
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
internal func cConnect (_ socketfd: Int32, _ addr: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    
    #if os(Linux)
    return Glibc.connect(socketfd, addr, length)
    #else
    return Darwin.connect(socketfd, addr, length)
    #endif
}
internal func cSend (_ socketfd: Int32, _ data: UnsafeRawPointer!, _ length: Int) -> Int {
    #if os(Linux)
    return Glibc.send(socketfd, data, length, Int32(MSG_NOSIGNAL))
    #else
    return Darwin.send(socketfd, data, length, MSG_SEND)
    #endif
}
