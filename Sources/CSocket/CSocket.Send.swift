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
        beginSend(data: &data, sync: true)
        
        defer {
            sendSM.signal()
        }
        
        if let err = sendErr {
            throw err
        }
    }
    
    public func sendAsync (data: inout Data) {
        
        var d = data
        self.queue.async {
            self.beginSend(data: &d, sync: false)
        }

    }
    private func beginSend (data: inout Data, sync: Bool) {
        sendSM.wait()
        
        self.sendTmpData = data
        self.sendTmpBytesSent = 0
        self.sendStartDate = Date()
        
        self.sendUpdate(sync: sync)
    }
    private func sendUpdate (sync: Bool) {
        
        guard let socketfd = fd.get() else {
            self.sendEnded(sync: sync, error: CSocket.Error.socketNotOpenError())
            return
        }
        
        if sendTimeout > 0.0 && Date().timeIntervalSince(sendStartDate) > sendTimeout {
            self.sendEnded(sync: sync, error: CSocket.Error.timedOutError())
            return
        }

        var writelen = 0
        sendTmpData.withUnsafeBytes { (p) -> Void in
            
            let addr = p.baseAddress!.advanced(by: sendTmpBytesSent)
            let bytesToSend = sendTmpData.count-sendTmpBytesSent
            
            #if os(Linux)
            writelen = Glibc.send(socketfd, addr, bytesToSend, Int32(MSG_NOSIGNAL))
            #else
            writelen = Darwin.send(socketfd, addr, bytesToSend, MSG_SEND)
            #endif
        }
       // var p = UnsafeRawPointer(&data).advanced(by: sendTmpBytesSent)

        if writelen <= 0 && errno != EWOULDBLOCK {
            let err = CSocket.Error.currentError()
            self.close()
            self.sendEnded(sync: sync, error: err)
            return
        }
        
        if writelen > 0 {
            sendTmpBytesSent += writelen
        }
        
        //incorrect, figure something
        if writelen < sendTmpData.count {
            
            if sync {
                usleep(useconds_t(CSocket.sendIntervalMS * 1000))
                sendUpdate(sync: sync)
            } else {
                let deadline = DispatchTime.now() + .milliseconds(CSocket.sendIntervalMS)
                self.queue.asyncAfter(deadline: deadline, execute: {
                    self.sendUpdate(sync: sync)
                })
            }

            
        } else {
            sendEnded(sync: sync, error: nil)
        }
        
    }
    
    func sendEnded (sync: Bool, error: CSocket.Error?) {
        
        ///print("send ended")
        
        if sync {
            sendErr = error
            sendTmpData.removeAll()
        } else {
            
            sendSM.signal()
            delegate?.sendEnded(socket: self, error: error)
        }
        
    }
}
