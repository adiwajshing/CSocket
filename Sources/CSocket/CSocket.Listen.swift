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

    ///open the socket up for listening
    /// - Parameter maxBacklog: the maximum number of clients the socket will keep waiting
    open func listen (maxBacklog: Int32) throws {
        
        if isConnected {
            throw CSocket.Error.alreadyConnected
        }
        
        //allocate an fd
        let socketfd = socket(CSocket.inetProtocol, sockStreamType, 0)
        
        //make sure the fd is reusable after it has been deallocated
        var reuseon:Int32 = 1
        setsockopt(socketfd, SOL_SOCKET, SO_REUSEADDR, &reuseon, socklen_t(MemoryLayout<Int32>.size))
        
        //make the socket non-blocking
        CSocket.makeNonBlocking(socket: socketfd)
        
        //create the sockaddr_in6 struct which stores information about our address & port
        var sa = sockaddr_in6.init()
        memset(&sa, 0, MemoryLayout.size(ofValue: sa))
        sa.sin6_family = sa_family_t(CSocket.inetProtocol)
        sa.sin6_addr = in6addr_any // set to any so that we can accept connections from everywhere
        sa.sin6_port = CSocket.porthtons(in_port_t(port))
        
        
        var addr = sockaddr.init() // make sockaddr struct, so that the c function can read this and bind our fd to the address & port specified
        memcpy(&addr, &sa, MemoryLayout.size(ofValue: sa))
        
        var r = bind(socketfd, &addr, socklen_t(MemoryLayout.size(ofValue: sa))) // bind to fd
        
        if r < 0 {
            throw CSocket.Error.current() //throw error if failed
        }
        
        /* for most C socket functions you have to explicitly mention the library,
         i.e. Glibc on Linux & Darwin on MacOS */
        
        #if os(Linux)
        r = Glibc.listen(socketfd, maxBacklog)
        #else
        r = Darwin.listen(socketfd, maxBacklog)
        #endif
        
        if r < 0 {
            throw CSocket.Error.current() //throw error if failed
        }
        
        //If all went well, set our socketfd to self.fd. Listening done successfully!
        fd.set(socketfd)
    }
    
    ///begins accepting clients in a non-block DispatchSourceTimer loop
    /// - Parameter intervalMS: the interval between each accept
    open func beginAcceptingLoop (intervalMS: Int = 100) {
        
        //makes a timer source
        let timer = DispatchSource.makeTimerSource(flags: [], queue: CSocket.updateQueue)
        
        //set some properties & start it
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMS), leeway: .milliseconds(10))
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
    
    ///Returns a connection if one was waiting, otherwise returns nil
    open func acceptAsync () throws -> CSocket? {
        
        guard let socketfd = fd.get() else {
            throw CSocket.Error.socketNotOpenError() //throw an exception if socket is not open
        }
        
        var cli_addr = sockaddr.init() //struct which stores information about the client
        var clilen = socklen_t(MemoryLayout.size(ofValue: cli_addr)) //size of structure mentioned above
        
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
            throw CSocket.Error.current() //if there was an error in connecting
        }
        
        CSocket.makeNonBlocking(socket: newsockfd) //make sure the incoming connection is made non-blocking
        
        var in_addr = sockaddr_in6.init() //since we're using IPV6 protocols, we use an IPV6 specific struct
        memcpy(&in_addr, &cli_addr, Int(clilen)) //copy the information to the IPV6 struct
        
        var clientip = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN)) //the ip address of the client
        if inet_ntop(CSocket.inetProtocol, &in_addr.sin6_addr, &clientip, socklen_t(INET6_ADDRSTRLEN)) == nil {
            throw CSocket.Error.failedToObtainIPAddress //throw an exception if the IP address could not be obtained
        }
        
        let clientport = Int32(in_addr.sin6_port) //the port on which the connection was accepted
        let clientaddr = String(cString: clientip) //cast the ip address as a swift string
        
        
        let socket = CSocket(address: clientaddr, port: clientport, addressType: .ipv6)
        socket.fd.set(newsockfd) //make CSocket wrap around the new fd
        
        return socket
    }
    
}
