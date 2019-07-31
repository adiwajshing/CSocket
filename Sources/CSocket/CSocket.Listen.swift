//
//  CSocket.Listen.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//
// Contains code for server side functionality like listening & accepting

#if os(Linux)
import Glibc
#else
import Darwin
#endif

import Foundation

extension CSocket {

    public func listen (maxBacklog: Int32) throws {
        
        if isConnected {
            throw CSocket.Error.alreadyConnected
        }
        
        let socketfd = socket(CSocket.inet_protocol, sockStreamType, 0)
        
        var reuseon:Int32 = 1
        setsockopt(socketfd, SOL_SOCKET, SO_REUSEADDR, &reuseon, socklen_t(MemoryLayout<Int32>.size))
        
        CSocket.makeNonBlocking(socket: socketfd)
        
        var sa = sockaddr_in6.init()
        memset(&sa, 0, MemoryLayout.size(ofValue: sa))
        sa.sin6_family = sa_family_t(CSocket.inet_protocol)
        sa.sin6_addr = in6addr_any
        sa.sin6_port = CSocket.porthtons(in_port_t(port))
        
        
        var addr = sockaddr.init()
        memcpy(&addr, &sa, MemoryLayout.size(ofValue: sa))
        
        let r = bind(socketfd, &addr, socklen_t(MemoryLayout.size(ofValue: sa)))
        
        if r < 0 {
            throw CSocket.Error.currentError()
        }
        
        #if os(Linux)
        let r0 = Glibc.listen(socketfd, maxBacklog)
        #else
        let r0 = Darwin.listen(socketfd, maxBacklog)
        #endif
        
        if r0 < 0 {
            throw CSocket.Error.currentError()
        }
        
        fd.set(socketfd)
    }
    
    public func beginAcceptingLoop (intervalMS: Int = 100) {
         
        let timer = DispatchSource.makeTimerSource(flags: [], queue: self.queue)
        
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMS), leeway: .milliseconds(30))
        timer.setEventHandler(handler: acceptLoop)
        timer.resume()
        
        self.dispatchSource = timer
    }
    private func acceptLoop () {
        if let client = try? acceptAsync() {
            self.acceptedClient(client: client)
        }
    }
    func acceptedClient (client: CSocket) {
        delegate?.didAcceptClient(socket: client)
    }
    
    public func acceptAsync () throws -> CSocket? {
        
        guard let socketfd = fd.get() else {
            throw CSocket.Error.socketNotOpenError() //throw an exception if socket is not open
        }
        
        var cli_addr = sockaddr.init() //struct which stores information about the client
        var clilen = socklen_t(MemoryLayout.size(ofValue: cli_addr))
        
        /* for most C socket functions you have to explicitly mention the library,
         i.e. Glibc on Linux & Darwin on MacOS */
        
        //accept the incoming connection & store the information about it in the sockaddr struct
        
        #if os(Linux)
        let newsockfd = Glibc.accept(socketfd, &cli_addr, &clilen)
        #else
        let newsockfd = Darwin.accept(socketfd, &cli_addr, &clilen)
        #endif
        
        //if there was an incoming connection that was accepted successfully it would be set to a file descriptor, which would be > 0
        guard newsockfd > 0 else {
            if errno == EWOULDBLOCK { //if there was no incoming connection
                return nil
            }
            throw CSocket.Error.currentError() //if there was an error in connecting
        }
        
        CSocket.makeNonBlocking(socket: newsockfd) //make sure the incoming connection is made non-blocking
        
        var in_addr = sockaddr_in6.init() //since we're using IPV6 protocols, we use an IPV6 specific struct
        memcpy(&in_addr, &cli_addr, Int(clilen)) //copy the information to the IPV6 struct
        
        var clientip = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN)) //the ip address of the client
        if inet_ntop(CSocket.inet_protocol, &in_addr.sin6_addr, &clientip, socklen_t(INET6_ADDRSTRLEN)) == nil {
            throw CSocket.Error.failedToObtainIPAddress //throw an exception if the IP address could not be obtained
        }
        
        let clientport = Int32(in_addr.sin6_port) //the port on which the connection was accepted
        let clientaddr = String(cString: clientip) //cast the ip address as a swift string
        
        let socket = CSocket(address: clientaddr, port: clientport, inet_protocol: CSocket.inet_protocol)
        socket.fd.set(newsockfd) 
        
        return socket
    }
    
}
