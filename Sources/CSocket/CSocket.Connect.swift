//
//  CSocket.Connect.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//  Code for connect & close functions

#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation
import Promises

extension CSocket {
    
    ///Connect to a listener asynchronously; calls connectEnded(socket:, error:) of the delegate
    open func connect (timeout: DispatchTimeInterval = .seconds(5)) -> Promise<Void> {
        
        let promise = Promise<Void>.pending()
        queue.async { self._connect(promise: promise, timeout: timeout) }
        return promise
    }
    private func _connect (promise: Promise<Void>, timeout: DispatchTimeInterval) {
        
        if let _ = fd.syncPointee { // if already connected
            promise.reject(CSocket.Error.alreadyConnected)
        } else {

            // make a sockaddr_in6 to input our IPV6 address information
            var addrIn = sockaddr_in6.init()
            addrIn.sin6_family = sa_family_t(CSocket.inetProtocol) // set protocol to IPV6
            inet_pton(AF_INET6, self.address, &addrIn.sin6_addr) // set address
            addrIn.sin6_port = CSocket.porthtons(in_port_t(self.port)) // convert port to network encoding and set it
            
            let socketfd = socket(CSocket.inetProtocol, sockStreamType, 0) // allocate an IPV6 socket fd
            CSocket.makeNonBlocking(socket: socketfd) // make it non-blocking
            
            var sa = sockaddr()
            memcpy(&sa, &addrIn, MemoryLayout<sockaddr_in6>.size) // copy address information
            let saSize = socklen_t(MemoryLayout.size(ofValue: addrIn)) // get size of the sockaddr_in6 struct
            let r = cConnect(socketfd, &sa, saSize)
            #if os(Linux)
            /*
             A SIGPIPE error is thrown when the socket is closed and one tries to read/write to it.
             We set it to SO_NOSIGPIPE to prevent that error from crashing the app.
             Otherwise, unexpected socket closes will crash the app
             */
            var set: Int32 = 0
            setsockopt(socketfd, SOL_SOCKET, SO_NOSIGPIPE, &set, socklen_t(MemoryLayout<Int32>.size))
            #endif
            
            if r > 0 { // r > 0, means the connection was successful
                promise.fulfill(())
            } else if errno == EINPROGRESS || errno == ENOTCONN {
                
                let source = DispatchSource.makeWriteSource(fileDescriptor: socketfd, queue: queue)
                let timer = timerForTimeout(timeout: timeout, source: source, promise: promise)
                
                source.setEventHandler {
                    // make a sockaddr_in6 to input our IPV6 address information
                    var addrIn = sockaddr_in6.init()
                    addrIn.sin6_family = sa_family_t(CSocket.inetProtocol) // set protocol to IPV6
                    inet_pton(AF_INET6, self.address, &addrIn.sin6_addr) // set address
                    addrIn.sin6_port = CSocket.porthtons(in_port_t(self.port)) // convert port to network encoding and set it
                    
                    var sa = sockaddr()
                    memcpy(&sa, &addrIn, MemoryLayout<sockaddr_in6>.size) // copy address
                    let re = cConnect(socketfd, &sa, saSize)
                   // let re = cSend(socketfd, &tmp, 0) //cSend(socketfd, &tmp, 0)
                    
                    if re > 0 || errno == EISCONN {
                        source.cancel()
                        timer?.cancel()
                        
                        // set the socketfd to our fd property
                        self.fd.syncPointee = socketfd

                        promise.fulfill(())
                    } else if errno != EWOULDBLOCK && errno != EINPROGRESS && errno != ENOTCONN {
                        source.cancel()
                        timer?.cancel()
                        
                        promise.reject(CSocket.Error.current())
                        self.close() // close the socket
                    }
                }
                
                timer?.resume()
                source.resume()
                
            } else {
                promise.reject(CSocket.Error.current())
                self.close() // close the socket
            }
        }
    }
    ///close the socket connection
    open func close () {
        
        guard let socketfd = fd.syncPointee else { return }
        
        dispatchSource?.cancel()
        
        #if os(Linux)
        Glibc.close(socketfd)
        #else
        Darwin.close(socketfd)
        #endif
        
        
        fd.syncPointee = nil
    }

    
}
