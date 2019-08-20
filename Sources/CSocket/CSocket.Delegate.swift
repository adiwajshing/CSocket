//
//  CSocket.Delegate.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/30/19.
//

import Foundation

///The protocol for all async operations on CSocket
public protocol CSocketAsyncOperationsDelegate: class {
    
    ///the callback event for when the socket connect attempt ends
    func connectEnded (socket: CSocket, error: CSocket.Error?)
    
    ///the callback event for when the socket send attempt ends
    func sendEnded (socket: CSocket, error: CSocket.Error?)
    
    ///the callback event for when the socket read attempt ends
    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?)
    
    ///the callback event for when the socket has data available to read
    func dataDidBecomeAvailable (socket: CSocket, bytes: Int)
    
    ///the callback event for when the listener accepts an incoming client
    func didAcceptClient (socket: CSocket)
}

// extension to make all functions optional
public extension CSocketAsyncOperationsDelegate {
    
    func connectEnded (socket: CSocket, error: CSocket.Error?) {
        
    }
    func sendEnded (socket: CSocket, error: CSocket.Error?) {
        
    }
    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?) {
        
    }
    
    func dataDidBecomeAvailable (socket: CSocket, bytes: Int) {
        
    }
    func didAcceptClient (socket: CSocket) {
        
    }
    
}
