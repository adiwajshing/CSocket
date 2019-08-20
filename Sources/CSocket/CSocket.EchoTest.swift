//
//  CSocket.EchoTest.swift
//  CSocket
//
//  Created by Adhiraj Singh on 8/11/19
//

import Foundation

extension CSocket {
    
    open func echoTestAsync () {
        sendAsync(data: &CSocket.echoTestBytes)
        readAsync(expectedLength: CSocket.echoTestBytes.count)
    }
    
    open func echoTestSync (timeout: Double) throws {
        sendAsync(data: &CSocket.echoTestBytes)
        
        readSM.wait()
        let oldTimeout = self.readTimeout
        self.readTimeout = timeout
        readSM.signal()
        
        _ = try readSync(expectedLength: CSocket.echoTestBytes.count)
        
        readSM.wait()
        self.readTimeout = oldTimeout
        readSM.signal()
    }
    
}
