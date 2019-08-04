//
//  ConnectingTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/30/19.
//

import XCTest
@testable import CSocket

class ConnectingTests: XCTestCase, CSocketAsyncOperationsDelegate {

    var hasConnected = false

    func testConnectAsync () {

        let socket: CSocket
        do {
            socket = try CSocket(host: "3.92.216.207", port: 8081)
        } catch {
            XCTFail("error in making socket: \(error)")
            return
        }
        
        socket.connectTimeout = 5.0
        socket.delegate = self
        socket.connectAsync()
        
        while !hasConnected {
            usleep(10 * 1000)
        }
        
        socket.close()
    }
    func connectEnded(socket: CSocket, error: CSocket.Error?) {
        hasConnected = true
        XCTAssertTrue(socket.isConnected, "socket connect failed, error: \(error!)")
    }
    
    func testConnectSync () {
        
        do {
            let socket = try CSocket(host: "3.92.216.207", port: 8081)
            socket.connectTimeout = 5.0
            
            try socket.connectSync()
            socket.close()
        } catch {
            XCTFail("got error: \(error)")
        }
        
    }
    
    func testConnectFail () {
        do {
            let socket = try CSocket(host: "3.92.216.27", port: 8081)
            socket.connectTimeout = 2.0
            
            try socket.connectSync()
            XCTFail("should have failed")
        } catch {
            print("got error: \(error)")
        }
    }
    
    static var allTests = [
        ("testConnectSync", testConnectSync),
        ("testConnectAsync", testConnectAsync),
        ("testConnectFail", testConnectFail)
    ]

}
