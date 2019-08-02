//
//  CSocket.Read.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//

import Foundation

extension CSocket {
    
    public func notifyOnDataAvailable (useDispatchSourceRead: Bool, intervalMS: Int = 100) throws {
        
        guard let socketfd = fd.get() else {
            throw CSocket.Error.socketNotOpenError()
        }
        
        if useDispatchSourceRead {
            
            let source = DispatchSource.makeReadSource(fileDescriptor: socketfd, queue: self.queue)
            source.setEventHandler(handler: gotData)
            source.resume()
            
            self.dispatchSource = source
        } else {
            let timer = DispatchSource.makeTimerSource(flags: [], queue: self.queue)
            
            timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMS), leeway: .milliseconds(30))
            timer.setEventHandler(handler: readLoop)
            timer.resume()
            
            self.dispatchSource = timer
        }

    }
    private func gotData () {
        
        let bytes = availableData()
        
        if bytes > 0 {
            self.dataDidBecomeAvailable(bytes: bytes)
        } else {
            //close()
           // self.dataDidBecomeAvailable(bytes: -1)
        }

    }
    private func readLoop () {

        let bytes = availableData()
        self.dataDidBecomeAvailable(bytes: bytes)
        
    }
    public func dataDidBecomeAvailable (bytes: Int) {
        delegate?.dataDidBecomeAvailable(socket: self, bytes: bytes)
    }
    
    public func readSync (expectedLength length: Int) throws -> Data {
        self.beginRead(length: length, sync: true)
        
        defer {
            readSM.signal()
        }
        
        if let err = readErr {
            throw err
        }
        
        let data = Data(tmpData)
        tmpData.removeAll()
        
        return data
    }

    public func readAsync (expectedLength length: Int) {
        
        self.queue.async {
            self.beginRead(length: length, sync: false)
        }

    }
    private func beginRead (length: Int, sync: Bool) {
        
        self.readSM.wait()
        
        self.tmpData = Data(count: length)
        
        self.tmpBytesRead = 0
        self.readStartDate = Date()
        
        self.dispatchSource?.suspend()
        
        self.readUpdate(sync: sync)
    }
    private func readUpdate (sync: Bool) {

        guard let socketfd = fd.get() else {
            self.readEnded(sync: sync, error: CSocket.Error.socketNotOpenError())
            return
        }
        
        if readTimeout > 0.0 && Date().timeIntervalSince(readStartDate) > readTimeout {
            self.readEnded(sync: sync, error: CSocket.Error.timedOutError())
            return
        }
        
        let bytesToRead = tmpData.count-tmpBytesRead
        var r = 0
        tmpData.withUnsafeMutableBytes { (p) -> Void in
            var addr = p.baseAddress!.advanced(by: tmpBytesRead)

            #if os(Linux)
            r = Glibc.recv(socketfd, addr, bytesToRead, 0)
            #else
            r = Darwin.recv(socketfd, addr, bytesToRead, 0)
            #endif
            
        }
        
        if r <= 0 && errno != EWOULDBLOCK  {
            let err = CSocket.Error.currentError()
            self.close()
            self.readEnded(sync: sync, error: err)
        } else {

            if r > 0 {
                tmpBytesRead += r
            }
            
            if tmpBytesRead < tmpData.count {
                
                if sync {
                    usleep(useconds_t(CSocket.readIntervalMS * 1000))
                    self.readUpdate(sync: sync)
                } else {
                    let deadline = DispatchTime.now() + .milliseconds(CSocket.readIntervalMS)
                    self.queue.asyncAfter(deadline: deadline, execute: {
                        self.readUpdate(sync: sync)
                    })
                }
                
                
            } else {
                readEnded(sync: sync, error: nil)
            }
            
        }
    }
    
    func readEnded (sync: Bool, error: CSocket.Error?) {
       // print("read ended")
        
        self.dispatchSource?.resume()
        
        if sync {
            readErr = error
        } else {
            let data = Data(tmpData)
            tmpData.removeAll()
            
            readSM.signal()
            delegate?.readEnded(socket: self, data: data, error: error)
        }
        
    }
    
}
