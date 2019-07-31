//
//  CSocket.Delegate.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/30/19.
//

import Foundation

public protocol SocketAsyncOperationsDelegate {
    func connectEnded (socket: CSocket, error: CSocket.Error?)
    func sendEnded (socket: CSocket, error: CSocket.Error?)
    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?)
    
    func dataDidBecomeAvailable (socket: CSocket, bytes: Int)
    func didAcceptClient (socket: CSocket)
}

extension SocketAsyncOperationsDelegate {
    
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
