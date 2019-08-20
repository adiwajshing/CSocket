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

extension CSocket {
    
    ///Connect to a listener synchronously
    open func connectSync () throws {
        beginConnect(sync: true)
        
        defer {
            readSM.signal() // signal the semaphore before exiting the function
        }
        
        if let err = readErr {
            throw err
        }
    }
    
    ///Connect to a listener asynchronously; calls connectEnded(socket:, error:) of the delegate
    open func connectAsync () {
        CSocket.updateQueue.async {
            self.beginConnect(sync: false)
        }
    }
    
    ///Begin connecting
    private func beginConnect (sync: Bool) {
        
        readSM.wait() //wait in case multiple threads simultaneously try to connect
        
        /*
         Using the Semaphore used for reading because reading will not be enabled till the socket is connected
         */
        
        if let _ = self.fd.get() { // if already connected
            self.connectEnded(sync: sync, error: CSocket.Error.alreadyConnected) //end with error
            return
        }
        
        // make a sockaddr_in6 to input our IPV6 address information
        var addrIn = sockaddr_in6.init()
        addrIn.sin6_family = sa_family_t(CSocket.inetProtocol) // set protocol to IPV6
        inet_pton(AF_INET6, self.address, &addrIn.sin6_addr) // set address
        addrIn.sin6_port = CSocket.porthtons(in_port_t(self.port)) // convert port to network encoding and set it
        
        let socketfd = socket(CSocket.inetProtocol, sockStreamType, 0) // allocate an IPV6 socket fd
        CSocket.makeNonBlocking(socket: socketfd) // make it non-blocking
        
        var sa = sockaddr.init()
        memcpy(&sa, &addrIn, MemoryLayout<sockaddr_in6>.size) // copy address information
        let saSize = socklen_t(MemoryLayout.size(ofValue: addrIn)) // get size of the sockaddr_in6 struct
        
        #if os(Linux)
        let r = Glibc.connect(socketfd, &sa, saSize)
        #else
        let r = Darwin.connect(socketfd, &sa, saSize) // connect
        
        /*
         A SIGPIPE error is thrown when the socket is closed and one tries to read/write to it.
         We set it to SO_NOSIGPIPE to prevent that error from crashing the app.
         Otherwise, unexpected socket closes will crash the app
         */
        var set: Int32 = 0
        setsockopt(socketfd, SOL_SOCKET, SO_NOSIGPIPE, &set, socklen_t(MemoryLayout<Int32>.size))
        
        #endif
        
        // set the socketfd to our fd property
        self.fd.set(socketfd)
        
        readStartDate = Date()
        //start the update loop
        self.connectUpdate(sync: sync, r: r, err: errno)
    }
    
    ///update loop that checks if the socket has connected
    /// - Parameter sync: whether the update loop should be synchronous or not
    /// - Parameter r: the result of the last connect check
    /// - Parameter err: the error (if any) from the last connect check
    private func connectUpdate (sync: Bool, r: Int32, err: Int32) {
        
        if r >= 0 { // r >= 0, means the connection was successful
            self.connectEnded(sync: sync, error: nil) // end the loop
        } else if err == EINPROGRESS || err == ENOTCONN { // if the connecting is in progress
            
            let timeSinceStart = Date().timeIntervalSince(readStartDate)
            
            if connectTimeout > 0 && timeSinceStart > connectTimeout { // if there was a timeout & the process has timed out
                close()
                self.connectEnded(sync: sync, error: CSocket.Error.timedOutError()) // finish loop with timeout error
            } else {
                
                guard let socketfd = fd.get() else { // check whether the fd is still set
                    self.connectEnded(sync: sync, error: CSocket.Error.socketNotOpenError()) // finish with notOpenError
                    return
                }
                
                
                /*
                 Attempt to send nothing as a way to check the connection
                 */
                
                var tmp = 0
                #if os(Linux)
                let r2 = Int32(Glibc.send(socketfd, &tmp, 0, Int32(MSG_NOSIGNAL)))
                // MSG_NOSIGNAL is the Linux way of saying don't call SIGPIPE
                #else
                let r2 = Int32(Darwin.send(socketfd, &tmp, 0, MSG_SEND))
                #endif
                
                let err2 = errno // get the error from the send attempt
                
                if sync {
                    // if sync, then sleep for a few MS and check connection again
                    usleep(useconds_t(CSocket.connectCheckIntervalMS * 1000))
                    connectUpdate(sync: sync, r: r2, err: err2)
                } else {
                    // if async, then schedule an async operation to check the connection again
                    let deadline = DispatchTime.now() + .milliseconds(CSocket.connectCheckIntervalMS)
                    CSocket.updateQueue.asyncAfter(deadline: deadline) {
                        self.connectUpdate(sync: sync, r: r2, err: err2)
                    }
                }
                
            }
            
            
        } else { // otherwise, there was an error in connecting
            let cErr = CSocket.Error(err) // wrap the error in a CSocket.Error
            
            close() // close the socket
            connectEnded(sync: sync, error: cErr) // finish the loop
        }
        
    }
    
    private func connectEnded (sync: Bool, error: CSocket.Error?) {

        if sync {
            //set the error for the sync function to access
            readErr = error
        } else {
            readSM.signal()
            delegate?.connectEnded(socket: self, error: error)
        }
        
    }
    
    ///close the socket connection
    open func close () {
        
        guard let socketfd = fd.get() else {
            return
        }
        
        #if os(Linux)
        Glibc.close(socketfd)
        #else
        Darwin.close(socketfd)
        #endif
        
        self.fd.set(nil)
    }

    
}
