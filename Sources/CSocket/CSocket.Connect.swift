//
//  CSocket.Connect.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//

#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation

extension CSocket {
    
    public func connectSync () throws {
        try syncOperation(asyncTask: {
            self.queue.async(execute: connectAsync)
        }, sm: self.readSM, error: &self.readErr, syncSwitch: &readSyncCall)
    }
    public func connectAsync () {
        
        self.queue.async {
            
            if let _ = self.fd.get() {
                self.connectEnded(error: CSocket.Error.alreadyConnected)
                return
            }
            
            var sa_f = sockaddr.init()
            
            var sa = sockaddr_in6.init()
            sa.sin6_family = sa_family_t(CSocket.inet_protocol)
            
            memset(&(sa.sin6_addr), 0, MemoryLayout.size(ofValue: sa.sin6_addr))
            inet_pton(AF_INET6, self.address, &(sa.sin6_addr))
            
            sa.sin6_port = CSocket.porthtons(in_port_t(self.port))
            
            memcpy(&sa_f, &sa, MemoryLayout<sockaddr_in6>.size)
            
            let socketfd = socket(CSocket.inet_protocol, sockStreamType, 0)
            CSocket.makeNonBlocking(socket: socketfd)
            
            let startDate = Date()
            
            let errorlen: socklen_t = UInt32(MemoryLayout<Int32>.size)
            
            #if os(Linux)
            let r = Glibc.connect(socketfd, &sa_f, socklen_t(MemoryLayout.size(ofValue: sa)))
            #else
            let r = Darwin.connect(socketfd, &sa_f, socklen_t(MemoryLayout.size(ofValue: sa)))
            
            var set: Int32 = 0
            setsockopt(socketfd, SOL_SOCKET, SO_NOSIGPIPE, &set, errorlen)
            
            #endif
            
            self.fd.set(socketfd)
            
            self.connectUpdate(startDate: startDate, r: r, err: errno)
            
        }
        
    }
    private func connectUpdate (startDate: Date, r: Int32, err: Int32) {
        
        if r >= 0 {
            self.connectEnded(error: nil)
        } else if err == EINPROGRESS || err == ENOTCONN {
            
            let timeSinceStart = Date().timeIntervalSince(startDate)
            if connectTimeout > 0 && timeSinceStart > connectTimeout {
                close()
                self.connectEnded(error: CSocket.Error.timedOutError())
            } else {

                guard let socketfd = fd.get() else {
                    self.connectEnded(error: CSocket.Error.socketNotOpenError())
                    return
                }
                
                var m = 0
                
                #if os(Linux)
                let r2 = Int32(Glibc.send(socketfd, &m, 0, Int32(MSG_NOSIGNAL)))
                #else
                let r2 = Int32(Darwin.send(socketfd, &m, 0, MSG_SEND))
                #endif
                
                let err2 = errno

                let deadline = DispatchTime.now() + .milliseconds(CSocket.connectCheckIntervalMS)
                self.queue.asyncAfter(deadline: deadline) {
                    self.connectUpdate(startDate: startDate, r: r2, err: err2)
                }
                
            }
            
            
        } else {
            let err = CSocket.Error.error(err)
            
            close()
            connectEnded(error: err)
        }
        
    }
    
    func connectEnded (error: CSocket.Error?) {
        
        //print("connect ended")
        
        if readSyncCall {
            readErr = error
            readSM.signal()
        } else if let delegate = delegate {
            delegate.connectEnded(socket: self, error: error)
        }
        
    }
    
    public func close () {
        
        guard let socketfd = fd.get() else {
            return
        }
        
        
        self.dispatchSource?.cancel()
        self.tmpData.removeAll()
        self.sendTmpData.removeAll()
        
        #if os(Linux)
        Glibc.close(socketfd)
        #else
        Darwin.close(socketfd)
        #endif
        
        self.fd.set(nil)

    }
    
}
