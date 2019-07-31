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

        try self.syncOperation(asyncTask: {
            self.readAsync(expectedLength: length)
        }, sm: self.readSM, error: &self.readErr, syncSwitch: &readSyncCall)

        let data = Data(bytes: &tmpData, count: tmpData.count)
        return data
    }

    public func readAsync (expectedLength length: Int) {
        
        self.queue.async {
            
            self.tmpData = [UInt8](repeating: 0, count: length)
            
            self.tmpBytesRead = 0
            self.readStartDate = Date()
            
            self.dispatchSource?.suspend()
            
            self.readUpdate()
            
        }

    }
    private func readUpdate () {

        guard let socketfd = fd.get() else {
            self.readEnded(error: CSocket.Error.socketNotOpenError())
            return
        }
        
        if readTimeout > 0.0 && Date().timeIntervalSince(readStartDate) > readTimeout {
            self.readEnded(error: CSocket.Error.timedOutError())
            return
        }
        
        #if os(Linux)
        let r = Glibc.recv(socketfd, &tmpData+tmpBytesRead, tmpData.count-tmpBytesRead, 0)
        #else
        let r = Darwin.recv(socketfd, &tmpData+tmpBytesRead, tmpData.count-tmpBytesRead, 0)
        #endif
        
        if r <= 0 && errno != EWOULDBLOCK  {
            let err = CSocket.Error.currentError()
            self.close()
            self.readEnded(error: err)
        } else {

            if r > 0 {
                tmpBytesRead += r
            }
            
            if tmpBytesRead < tmpData.count {
                let deadline = DispatchTime.now() + .milliseconds(CSocket.readIntervalMS)
                self.queue.asyncAfter(deadline: deadline, execute: self.readUpdate)
            } else {
                readEnded(error: nil)
            }
            
        }
    }
    
    func readEnded (error: CSocket.Error?) {
       // print("read ended")
        
        self.dispatchSource?.resume()
        
        if let delegate = delegate, !readSyncCall {
            let data = Data(bytes: &tmpData, count: tmpData.count)
            tmpData.removeAll()
            
            delegate.readEnded(socket: self, data: data, error: error)
        } else if readSyncCall {
            readErr = error
            
            readSM.signal()
        }
        
        
    }
    
}
