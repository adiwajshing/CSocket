//
//  ConnectingTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/30/19.
//

import XCTest
import Promises
@testable import CSocket

class ConnectingTests: XCTestCase {

    var clients = [CSocket]()
    
    func testConnect () throws {
        clients = try (0..<20).map { _ in try CSocket(host: "www.google.com", port: 80) }
        let promises = clients.map { $0.connect(timeout: .seconds(5))  }
        for p in promises {
             try await( p )
        }
        clients.removeAll()
    }

    func testConnectFail () {
        do {
            let socket = try CSocket(host: "3.92.216.27", port: 8081)
            
            try await(socket.connect(timeout: .seconds(2)))
            XCTFail("should have failed")
        } catch {
            print("got error: \(error)")
        }
    }
    
    static var allTests = [
        ("testConnect", testConnect),
        ("testConnectFail", testConnectFail)
    ]

}
