//
//  CSocket.Read.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//  Code for reading data

import Foundation
import Promises

extension CSocket {
    
    open func read (expectedCount count: Int, timeout: DispatchTimeInterval) -> Promise<Data> {

        let promise = Promise<Data>.pending()
        queue.async { self._read(count: count, promise: promise, timeout: timeout) }
        return promise
    }
    private func _read (count: Int, promise: Promise<Data>, timeout: DispatchTimeInterval) {
        
        var data = Data(count: count)
        var bytesRead = 0
        
        if let socketfd = fd.syncPointee {
            let source = DispatchSource.makeReadSource(fileDescriptor: socketfd, queue: queue)
            let timer = timerForTimeout(timeout: timeout, source: source, promise: promise)
            source.setEventHandler {
                
                if self.availableData() == 0 {
                    source.cancel()
                    timer?.cancel()
                    
                    promise.reject(CSocket.Error.init(ECONNRESET))
                    self.close()
                    return
                }
                
                let bytesToRead = data.count-bytesRead // the bytes left to read
                var r = 0 // result of the read
                 
                 data.withUnsafeMutableBytes { pointer in
                    // pick up reading from where it was left off
                     var addr = pointer.baseAddress!.advanced(by: bytesRead)
                     #if os(Linux)
                     r = Glibc.recv(socketfd, addr, bytesToRead, 0)
                     #else
                     r = Darwin.recv(socketfd, addr, bytesToRead, 0)
                     #endif
                 }
                    
                 // if bytes were read, add
                 if r > 0 { bytesRead += r }
                
                 if bytesRead >= data.count {
                    source.cancel()
                    timer?.cancel()
                    
                    promise.fulfill(data)
                 } else if errno != EWOULDBLOCK {
                   // print("\(self.description) ERROR \(Error.current())")
                    source.cancel()
                    timer?.cancel()
                    
                    promise.reject(Error.current())
                    self.close()
                 }
            }
            timer?.resume()
            source.resume()

        } else {
            promise.reject(Error.socketNotOpen)
        }
    }
    
}
