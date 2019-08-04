//
//  ReadingTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/30/19.
//

import XCTest
@testable import CSocket

class ReadingTests: XCTestCase, CSocketAsyncOperationsDelegate {
    
    var listener: CSocket!
    var client: CSocket!
    
    var data = Data(count: 1024 * 20) //use 20KB of data to transfer
    var rdata = Data()
    
    var isDoingSyncReading = false
    var isDone = false
    
    var isReading = false
    
    let iterations = 16 //use 16 read functions, to test how the socket performs with concurrent operations
    
    let queue = DispatchQueue(label: "test", attributes: [])
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        listener = CSocket(port: 8888)
        try! listener.listen(maxBacklog: 128)
        listener.delegate = self
        
        for i in 0..<data.count {
            data[i] = UInt8(((i % 256) + i) % 256)
        }
        
        listener.beginAcceptingLoop()
        
    }
    func heapSize(_ obj: AnyObject) -> Int {
        return malloc_size(Unmanaged.passRetained(obj).toOpaque())
    }
    
    func didAcceptClient(socket: CSocket) {
        print("accepted: \(socket.description)")
        
        socket.delegate = self
        socket.sendAsync(data: &data)
    }
    func sendEnded(socket: CSocket, error: CSocket.Error?) {
        print("sent \(socket.description)")
    }
    override func tearDown() {
        listener.close()
        client.close()
    }

    func testReadAsyncConcurrent() {
        client = try! CSocket(host: "::1", port: 8888)
        client.delegate = self
        client.connectAsync()
        
        while !isDone {
            usleep(100 * 1000)
        }
    }
    func testReadSync() throws {
        isDoingSyncReading = true
        
        client = try CSocket(host: "::1", port: 8888)
        client.delegate = self
        try client.connectSync()
        
        for _ in 0..<iterations {
            let d = try client.readSync(expectedLength: data.count/iterations)
            rdata.append(d)
        }
        
     //   print("\([UInt8](rdata))\n\([UInt8](data))")
        
        XCTAssertEqual(rdata, self.data)
    }
    func testReadSyncConcurrent() throws {
        isDoingSyncReading = true
        
        client = try CSocket(host: "::1", port: 8888)
        client.delegate = self
        try client.connectSync()
        
        var iterationsDone = 0
        DispatchQueue.concurrentPerform(iterations: iterations) { (_) in
            do {
                let d = try self.client.readSync(expectedLength: self.data.count/self.iterations)
                
                self.queue.async {
                    self.rdata.append(d)
                    iterationsDone += 1
                }
            } catch {
                XCTFail("reading error: \(error)")
            }
        }
        
        while iterationsDone < iterations {
            usleep(100 * 1000)
        }

        XCTAssertEqual(rdata, self.data)
    }
    func testReadingNotifications () throws {
        isDoingSyncReading = false
        
        client = try CSocket(host: "::1", port: 8888)
        client.delegate = self
        try client.connectSync()
        try client.notifyOnDataAvailable(useDispatchSourceRead: false, intervalMS: 100)
        
        while !isDone {
            usleep(100 * 1000)
        }
    }
    func testReadingNotificationsReadSource () throws {
        isDoingSyncReading = false
        
        client = try CSocket(host: "::1", port: 8888)
        client.delegate = self
        try client.connectSync()
        try client.notifyOnDataAvailable(useDispatchSourceRead: true)
        
        while !isDone {
            usleep(100 * 1000)
        }
    }
    func dataDidBecomeAvailable(socket: CSocket, bytes: Int) {
        XCTAssertNotEqual(bytes, 0)
        XCTAssertFalse(isReading)
        
        if bytes < 0 {
            return
        }
        
        isReading = true
        client.readAsync(expectedLength: data.count/iterations)
    }
    
    func connectEnded(socket: CSocket, error: CSocket.Error?) {
        XCTAssertFalse(isDoingSyncReading)
        XCTAssertNil(error, "connect error: \(error!)")
        
        DispatchQueue.concurrentPerform(iterations: iterations) { (_) in
            let c = data.count/self.iterations
            client.readAsync(expectedLength: c)
        }
    }
    func readEnded(socket: CSocket, data: Data, error: CSocket.Error?) {
        
        XCTAssertFalse(isDoingSyncReading)
        XCTAssertNil(error, "got error: \(error!)")
        
        isReading = false
        
        self.queue.async {
            self.rdata.append(data)
            
            if self.rdata.count == self.data.count {
                
                XCTAssertEqual(self.rdata, self.data)
                self.isDone = true
            }
        }
        
    }
    
    static var allTests = [
        ("testReadSync", testReadSync),
        ("testReadAsync", testReadAsyncConcurrent),
        ("testReadNotifications", testReadingNotifications)
    ]

}
