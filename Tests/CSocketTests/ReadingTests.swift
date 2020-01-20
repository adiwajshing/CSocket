//
//  ReadingTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/30/19.
//

import XCTest
import Promises
@testable import CSocket

class ReadingTests: XCTestCase {
    
    var listener: CSocket!
    
    var data = Data(count: 1024*1024) //use 1MB of data to transfer
    
    let iterations = 16 //use 16 read functions, to test how the socket performs with many read operations
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        listener = CSocket(port: 8888)
        try! listener.listen(maxBacklog: 128)
        
        for i in 0..<data.count { data[i] = UInt8(((i % 256) + i) % 256) }
        
        listener.beginAcceptingLoop(didAcceptClient: didAcceptClient)
        
    }
    func heapSize(_ obj: AnyObject) -> Int { malloc_size(Unmanaged.passRetained(obj).toOpaque()) }
    
    func didAcceptClient(result: Result<CSocket, Error>) {
        switch result {
        case .success(let socket):
            print("accepted: \(socket.description)")
            _ = socket.send(data: data, timeout: .seconds(5)).then(on: socket.queue) { print("sent \(socket.description)") }
            break
        case .failure(let error):
            XCTFail("ERROR: \(error)")
            break
        }
    }

    func testReadInBlocks() throws {
        let client = try CSocket(host: "::1", port: 8888)
        var promise = client.connect().then (on: client.queue) { print("connected") }
        
        var readData = Data()
        
        let blockSize = data.count/self.iterations
        for _ in 0..<iterations {
            promise = promise
                .then (on: client.queue) { _ in client.read(expectedCount: blockSize, timeout: .seconds(2)) }
                .then (on: client.queue) { readData.append($0) }
        }
        
        try await(promise)
        
        XCTAssertEqual(readData, data)
        client.close()
    }
    
    override func tearDown() {
        listener.close()
    }
    
    /*static var allTests = [
        ("testReadSync", testReadSync),
        ("testReadAsync", testReadAsyncConcurrent),
        ("testReadNotifications", testReadingNotifications)
    ]*/

}
