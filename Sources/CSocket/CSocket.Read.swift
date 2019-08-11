//
//  CSocket.Read.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//  Code for reading data

import Foundation

extension CSocket {
    
    ///notify when data is available to read; calls dataDidBecomeAvailable (socket:, bytes:)
    ///see 'CSocket.readBytesThreshhold' to tune the minimum data you need for the callback to be triggered
    /// - Parameter useDispatchSourceRead: Whether to use a DispatchSourceTimer or use the DispatchSourceRead (note: in my experience, DispatchSourceRead can be buggy on Linux)
    /// - Parameter intervalMS: Interval in MS between which it will check for data available, only valid for DispatchSourceTimer
    public func notifyOnDataAvailable (useDispatchSourceRead: Bool, intervalMS: Int = 100) throws {
        
        guard let socketfd = fd.get() else { // if the socket is not open
            throw CSocket.Error.socketNotOpenError() // throw error
        }
        
        if useDispatchSourceRead {
            
            let source = DispatchSource.makeReadSource(fileDescriptor: socketfd, queue: CSocket.updateQueue)
            source.setEventHandler(handler: gotData)
            source.resume()
            
            self.dispatchSource = source
        } else {
            let timer = DispatchSource.makeTimerSource(flags: [], queue: CSocket.updateQueue)
            
            timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMS), leeway: .milliseconds(30))
            timer.setEventHandler(handler: readLoop)
            timer.resume()
            
            self.dispatchSource = timer
        }

    }
    ///handler for DispatchSourceRead
    private func gotData () {
        
        let bytes = availableData()
        
        if bytes >= self.readBytesThreshhold {
            delegate?.dataDidBecomeAvailable(socket: self, bytes: bytes)
        }

    }
    ///handler for DispatchSourceTimer
    private func readLoop () {

        let bytes = availableData() // get the available data
        
        if bytes >= self.readBytesThreshhold { // check if beyond threshhold
            delegate?.dataDidBecomeAvailable(socket: self, bytes: bytes)  // callback if is
        }
        
    }
    
    ///read data synchronously.
    ///see CSocket.readTimeout to set a timeout
    /// - Parameter expectedLength: the number of bytes that are expected from the other side
    public func readSync (expectedLength length: Int) throws -> Data {
        self.beginRead(length: length, sync: true)
        
        defer {
            tmpData.removeAll()
            readSM.signal()
        }
        
        if let err = readErr {
            throw err
        }
        
        let data = Data(tmpData) // copy data
        return data
    }

    public func readAsync (expectedLength length: Int) {
        
        CSocket.updateQueue.async {
            self.beginRead(length: length, sync: false)
        }

    }
    private func beginRead (length: Int, sync: Bool) {
        
        self.readSM.wait()
        
        
        self.tmpData = Data(count: length) // create tmp data to store the bytes read
        self.tmpBytesRead = 0
        
        self.readStartDate = Date() // set the start date
        
        self.dispatchSource?.suspend() // pause the read loop because we need this read to finish before preparing for another one
        
        self.readUpdate(sync: sync)
    }
    
    ///update loop that repeatedly tries to read data
    /// - Parameter sync: whether the update loop should be synchronous or not
    private func readUpdate (sync: Bool) {

        guard let socketfd = fd.get() else { // if socket is not open
            self.readEnded(sync: sync, error: CSocket.Error.socketNotOpenError())
            return
        }
        
        if readTimeout > 0.0 && Date().timeIntervalSince(readStartDate) > readTimeout {  // if there was a timeout & the process has timed out
            self.close()
            self.readEnded(sync: sync, error: CSocket.Error.timedOutError())
            return
        }
        
        
        let bytesToRead = tmpData.count-tmpBytesRead // the bytes left to read
        var r = 0 // result of the read
        tmpData.withUnsafeMutableBytes { (p) -> Void in
            // from where we need to pick up reading, because sometimes all the data isn't recieved at once
            var addr = p.baseAddress!.advanced(by: tmpBytesRead)

            #if os(Linux)
            r = Glibc.recv(socketfd, addr, bytesToRead, 0)
            #else
            r = Darwin.recv(socketfd, addr, bytesToRead, 0)
            #endif
            
        }
        
        if r > 0 { // if bytes were read
            tmpBytesRead += r // add to already bytes read
        }
        
        if r <= 0 && errno != EWOULDBLOCK  { // if there was an error
            let err = CSocket.Error.current()
            self.close()
            self.readEnded(sync: sync, error: err)
        } else if tmpBytesRead < tmpData.count {
            
            if sync {
                // sleep a lil before checking for data again
                usleep(useconds_t(CSocket.readIntervalMS * 1000))
                self.readUpdate(sync: sync)
            } else {
                // schedule a read again in a few MS
                let deadline = DispatchTime.now() + .milliseconds(CSocket.readIntervalMS)
                CSocket.updateQueue.asyncAfter(deadline: deadline, execute: {
                    self.readUpdate(sync: sync)
                })
            }
            
            
        } else { // if reading is complete
            readEnded(sync: sync, error: nil) // finish with no error
        }
    }
    
    private func readEnded (sync: Bool, error: CSocket.Error?) {
        
        self.dispatchSource?.resume() // resume the read loop once this read is over
        
        if sync {
            readErr = error
        } else {
            let data = Data(tmpData) // copy the data into a tmp variable
            tmpData.removeAll()
            
            readSM.signal()
            
            delegate?.readEnded(socket: self, data: data, error: error)
            
        }
        
    }
    
}
