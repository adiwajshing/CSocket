//
//  CSocket.Send.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//  Code for sending data

#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation

extension CSocket {
    
    ///send data synchronously.
    ///see CSocket.sendTimeout to set a timeout
    public func sendSync (data: inout Data) throws {
        beginSend(data: &data, sync: true) // send the data
        
        defer {
            sendSM.signal()
        }
        
        if let err = sendErr { // sendErr is set when the send is complete
            throw err
        }
    }
    
    ///send data asynchronously; calls the sendEnded (socket:, error:) when done.
    ///see CSocket.sendTimeout to set a timeout
    public func sendAsync (data: inout Data) {
        
        var d = data
        CSocket.updateQueue.async {
            self.beginSend(data: &d, sync: false)
        }

    }
    
    ///begin sending data
    private func beginSend (data: inout Data, sync: Bool) {
        sendSM.wait()
        
        self.sendTmpData = data
        self.sendTmpBytesSent = 0
        self.sendStartDate = Date()
        
        self.sendUpdate(sync: sync)
    }
    ///update loop that repeatedly tries to send all the data
    /// - Parameter sync: whether the update loop should be synchronous or not
    private func sendUpdate (sync: Bool) {
        
        if sendTimeout > 0.0 && Date().timeIntervalSince(sendStartDate) > sendTimeout { // if there was a timeout & the process has timed out
            self.sendEnded(sync: sync, error: CSocket.Error.timedOutError())
        } else if let socketfd = fd.get() {
            
            var writelen = 0
            sendTmpData.withUnsafeBytes { (p) -> Void in // access the raw bytes from the data
                
                let addr = p.baseAddress!.advanced(by: sendTmpBytesSent) // move the pointer forward to from where we want to send the data
                let bytesLeftToSend = sendTmpData.count-sendTmpBytesSent
                
                #if os(Linux)
                writelen = Glibc.send(socketfd, addr, bytesLeftToSend, Int32(MSG_NOSIGNAL))
                #else
                writelen = Darwin.send(socketfd, addr, bytesLeftToSend, MSG_SEND)
                #endif
            }
            
            if writelen > 0 { // if data was written, up the number of bytes sent
                sendTmpBytesSent += writelen
            }
            
            if writelen <= 0 && errno != EWOULDBLOCK { // if there was an error
                
                let err = CSocket.Error.current()
                self.close()
                self.sendEnded(sync: sync, error: err) // finish with error
            } else if sendTmpBytesSent < sendTmpData.count { // if there is still data left to send
                
                //incorrect, figure something
                
                if sync {
                    usleep(useconds_t(CSocket.sendIntervalMS * 1000)) // sleep for a few MS
                    sendUpdate(sync: sync) // send data again
                } else {
                    let deadline = DispatchTime.now() + .milliseconds(CSocket.sendIntervalMS)
                    CSocket.updateQueue.asyncAfter(deadline: deadline, execute: {
                        self.sendUpdate(sync: sync)
                    })
                }
                
                
            } else { // all data has been sent successfully
                sendEnded(sync: sync, error: nil) // finish success
            }
            
        } else {
            self.sendEnded(sync: sync, error: CSocket.Error.socketNotOpenError())
        }

        
    }
    
    private func sendEnded (sync: Bool, error: CSocket.Error?) {

        if sync {
            sendErr = error // set the error for the sync function to access
            sendTmpData.removeAll()
        } else {
            sendSM.signal() // signal the semaphore and call the completion
            delegate?.sendEnded(socket: self, error: error)
        }
        
    }
}
