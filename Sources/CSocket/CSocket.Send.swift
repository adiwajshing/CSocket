//
//  CSocket.Send.swift
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
    
    public func sendSync (data: inout Data) throws {
        try syncOperation(asyncTask: {
            self.sendAsync(data: &data)
        }, sm: self.sendSM, error: &self.sendErr, syncSwitch: &sendSyncCall)
    }
    public func sendAsync (data: inout Data) {
        var bytes = [UInt8](data)
        sendAsync(bytes: &bytes)
    }
    public func sendAsync (bytes: inout [UInt8]) {
        
        let b = bytes
        
        self.queue.async {
            
            self.sendTmpData = b
            self.sendTmpBytesSent = 0
            self.sendStartDate = Date()
            
            self.sendUpdate()
        }

    }
    private func sendUpdate () {
        
        guard let socketfd = fd.get() else {
            self.sendEnded(error: CSocket.Error.socketNotOpenError())
            return
        }
        
        if sendTimeout > 0.0 && Date().timeIntervalSince(sendStartDate) > sendTimeout {
            self.sendEnded(error: CSocket.Error.timedOutError())
            return
        }
        
        #if os(Linux)
        let writelen = Glibc.send(socketfd, &sendTmpData+sendTmpBytesSent, sendTmpData.count-sendTmpBytesSent, Int32(MSG_NOSIGNAL))
        #else
        let writelen = Darwin.send(socketfd, &sendTmpData+sendTmpBytesSent, sendTmpData.count-sendTmpBytesSent, MSG_SEND)
        #endif
        
        if writelen <= 0 && errno != EWOULDBLOCK {
            let err = CSocket.Error.currentError()
            self.close()
            self.sendEnded(error: err)
            return
        }
        
        if writelen > 0 {
            sendTmpBytesSent += writelen
        }
        
        //incorrect, figure something
        if writelen < sendTmpData.count {

            let deadline = DispatchTime.now() + .milliseconds(CSocket.sendIntervalMS)
            self.queue.asyncAfter(deadline: deadline, execute: sendUpdate)
        } else {
            sendEnded(error: nil)
        }
        
    }
    
    func sendEnded (error: CSocket.Error?) {
        
        ///print("send ended")
        
        if sendSyncCall {
            sendErr = error
            sendTmpData.removeAll()
            
            sendSM.signal()
        } else if let delegate = delegate {
            delegate.sendEnded(socket: self, error: error)
        }
        
    }
}
