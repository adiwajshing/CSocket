//
//  CommunicationTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/31/19.
//
// Send two numbers to the server, server will add them; load test also

import XCTest
import Promises
@testable import CSocket

class CommunicationTests: XCTestCase {

    var server: Server!
    
    override func setUp() { server = Server(port: 8888) }

    override func tearDown() { server.close() }

    func testSingleClient() throws {
        try testClients(numberOfClients: 1)
    }
    func testMultipleClients () throws {
        try testClients(numberOfClients: 4000)
    }
    func testClients (numberOfClients: Int) throws {
        
        let clients = try (0..<numberOfClients).map { _ in try Client(host: "::1", port: 8888) }
        
        let promises = try clients.map { client -> Promise<Void> in
            var p = client.connect(timeout: .seconds(10))
            try await(p)
            
            for _ in 0..<20 {
                p = p.then (on: client.queue, client.testMultiplyRandomNumbers)
            }
            p = p.then (on: client.queue, client.close)
            
            return p
        }
        for p in promises {
            do {
               _ = try await(p)
            } catch  {
                print("CAUGHT ERROR: \(error)")
               // XCTFail("ERROR: \(error)")
            }
        }
       /* do {
           _ = try await(all(on: .global(), promises))
        } catch  {
            //XCTFail("ERROR: \(error)")
        }*/
        
    }
        
    class Server: CSocket {
        
        var clients = [CSocket]()
        let addingQueue = DispatchQueue(label: "a_queue", attributes: [])
        
        override init(port: Int32) {
            super.init(port: port)
            try! listen(maxBacklog: 4096)
            self.beginAcceptingLoop(didAcceptClient: didAcceptClient)
        }
        func didAcceptClient(result: Result<CSocket, Swift.Error>) {
            switch result {
            case .success(let socket):
                
                print("connected: \(socket.description)")
                self.read(socket: socket)
                break
            case .failure(let error):
                
                XCTFail("ERROR: \(error)")
                break
            }
        }
        func read(socket: CSocket) {

            _ = socket.read(expectedCount: MemoryLayout<Int32>.size*2, timeout: .seconds(100))
            .then (on: socket.queue) { data -> Promise<Void> in
                let num1: Int32 = fromData(value: Data(data[0..<MemoryLayout<Int32>.size]))
                let num2: Int32 = fromData(value: Data(data[4..<8]))
                    
                let result = Int64(num1 * num2)
                    
                print("\(socket.description) \(num1)*\(num2)=\(result)")
                return socket.send(data: toData(value: result), timeout: .seconds(5))
            }
            .then (on: socket.queue) { self.read(socket: socket) }
            .catch (on: socket.queue) { error -> Void in
                print("ERR: \(error), closing...")
                socket.close()
            }
            
        }
    }
    
    class Client: CSocket {
        
        var numbersMultiplied = 0
        
        func testMultiplyRandomNumbers () -> Promise<Void> {

            let num1: Int32 = Int32(arc4random() % 10000)
            let num2: Int32 = Int32(arc4random() % 10000)
            
            return multiplyNumbers(num1: num1, num2: num2)
                .then (on: queue) { XCTAssertEqual($0, Int64(num1)*Int64(num2)) }

        }
        func multiplyNumbers (num1: Int32, num2: Int32) -> Promise<Int64> {
            var data = Data()
            data.append(contentsOf: toData(value: num1))
            data.append(contentsOf: toData(value: num2))
            
            return send(data: data, timeout: .seconds(10))
            .then (on: queue) { self.read(expectedCount: MemoryLayout<Int64>.size, timeout: .seconds(10)) }
            .then (on: queue) { $0.withUnsafeBytes { p in p.baseAddress!.load(as: Int64.self) } }
        }
        
    }

}

func toData<T>(value: T) -> Data {
    var x = value
    return withUnsafeBytes(of: &x) { Data($0) }
}
func fromData<T>(value: Data) -> T {
    
    return value.withUnsafeBytes {
        $0.baseAddress!.load(as: T.self)
    }
}
