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
import Promises

extension CSocket {
    
    ///Send the data asynchronously
    open func send (data: Data, timeout: DispatchTimeInterval) -> Promise<Void> {
        let promise = Promise<Void>.pending()
        queue.async { self._send(data: data, promise: promise, timeout: timeout) }
        return promise
    }
    private func _send(data: Data, promise: Promise<Void>, timeout: DispatchTimeInterval) {
        
        var bytesSent = 0
        
        if let socketfd = self.fd.syncPointee {
            let source = DispatchSource.makeWriteSource(fileDescriptor: socketfd, queue: queue)
            let timer = timerForTimeout(timeout: timeout, source: source, promise: promise)
            
            source.setEventHandler {
                var writelen = 0
                data.withUnsafeBytes { (p) -> Void in
                    // access the raw bytes from the data, move the pointer forward to from where we want to send the data
                    let addr = p.baseAddress!.advanced(by: bytesSent)
                    writelen = cSend(socketfd, addr, data.count-bytesSent)
                }
                
                // if data was written, up the number of bytes sent
                if writelen > 0 { bytesSent += writelen }
                
                if writelen <= 0 && errno != EWOULDBLOCK && errno != EAGAIN { // if there was an error
                    source.cancel()
                    timer?.cancel()
                    
                    promise.reject(Error.current())
                    self.close()
                } else if bytesSent >= data.count {
                    source.cancel()
                    timer?.cancel()
                    
                    promise.fulfill(())
                }
            }
            timer?.resume()
            source.resume()
        } else {
            promise.reject(Error.socketNotOpen)
        }
    }

}
