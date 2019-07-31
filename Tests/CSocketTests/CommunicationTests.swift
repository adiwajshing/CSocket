//
//  CommunicationTests.swift
//  CSocketTests
//
//  Created by Adhiraj Singh on 7/31/19.
//
// Send two numbers to the server, server will add them

import XCTest
@testable import CSocket

class CommunicationTests: XCTestCase, SocketAsyncOperationsDelegate {

    var server: Server!
    var clients = [Client]()
    
    let numberOfClients = 1000
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        server = Server(port: 8888)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        server.close()
    }

    func testSingleClientSync() throws {

        let client = try Client(host: "::1", port: 8888)
        
        let num1: Int32 = 500
        let num2: Int32 = 230
        let r = try client.multiplyNumbersSync(num1: num1, num2: num2)
        XCTAssertEqual(r, Int64(num1*num2))
        
        client.close()
    }
    func testMultipleClientsSync () {
        
        DispatchQueue.concurrentPerform(iterations: numberOfClients) { (_) in
            
            do {
                let client = try Client(host: "::1", port: 8888)
                
                for _ in 0..<2 {
                    let num1: Int32 = Int32(arc4random() % 10000)
                    let num2: Int32 = Int32(arc4random() % 10000)
                    
                    let r = try client.multiplyNumbersSync(num1: num1, num2: num2)
                    XCTAssertEqual(r, Int64(num1*num2))
                }

                client.close()
            } catch {
                XCTFail("\(error)")
            }
            
        }
        
    }
    func testMultipleClientsAsync () {
        
        DispatchQueue.concurrentPerform(iterations: numberOfClients) { (_) in
            
            do {
                let client = try Client(host: "::1", port: 8888)
                self.numberMultiplied(client: client)
                
            } catch {
                XCTFail("\(error)")
            }
            
        }
    }
    
    func numberMultiplied (client: Client) {
        let num1: Int32 = Int32(arc4random() % 10000)
        let num2: Int32 = Int32(arc4random() % 10000)
        
        client.multiplyNumbersAsync(num1: num1, num2: num2) { (client, r, error) in
            XCTAssertNil(error, "error in number \(error!)")
            XCTAssertEqual(r, Int64(num1*num2))
            
            if client.numbersMultiplied < 2 {
                self.numberMultiplied(client: client)
            } else {
                client.close()
            }
        }
    }
    
    class Server: CSocket, SocketAsyncOperationsDelegate {
        
        
        override init(port: Int32) {
            super.init(port: port)
            try! listen(maxBacklog: 128)
            self.delegate = self
            
            self.beginAcceptingLoop(intervalMS: 10)
        }
        func didAcceptClient(socket: CSocket) {
            print("connected: \(socket.description)")
            socket.delegate = self
            
            try! socket.notifyOnDataAvailable(useDispatchSourceRead: false, intervalMS: 50)
            
        }
        func dataDidBecomeAvailable(socket: CSocket, bytes: Int) {
            
            if bytes > 0 {
                socket.readAsync(expectedLength: MemoryLayout<Int32>.size * 2)
            }

        }
        func readEnded(socket: CSocket, data: Data, error: CSocket.Error?) {
            var bytes = [UInt8](data)
            let num1: Int32 = fromByteArray(value: bytes[0..<MemoryLayout<Int32>.size])
            let num2: Int32 = fromByteArray(value: bytes[4..<8])
            
            let result = Int64(num1 * num2)
            
            print("\(socket.description) \(num1)*\(num2)=\(result)")
            
            bytes = toByteArray(value: result)
            socket.sendAsync(bytes: &bytes)
        }
        
    }
    
    class Client: CSocket, SocketAsyncOperationsDelegate {
        
        var numbersMultiplied = 0
        var asyncCallback: ((Client, Int64, CSocket.Error?) -> Void)?
        
        override init(host: String, port: Int32) throws {
            try super.init(host: host, port: port)
            self.delegate = self
            
            try connectSync()
        }
        func multiplyNumbersSync (num1: Int32, num2: Int32) throws -> Int64 {
            var bytes: [UInt8] = []
            bytes.append(contentsOf: toByteArray(value: num1))
            bytes.append(contentsOf: toByteArray(value: num2))
            
            var data = Data(bytes: &bytes, count: bytes.count)

            try sendSync(data: &data)
            let rdata = try readSync(expectedLength: MemoryLayout<Int64>.size)

            let value = rdata.withUnsafeBytes { (p) -> Int64 in
                return p.baseAddress!.load(as: Int64.self)
            }
            
            return value
        }
        
        func multiplyNumbersAsync (num1: Int32, num2: Int32, callback: @escaping ((Client, Int64, CSocket.Error?) -> Void)) {
            
            self.asyncCallback = callback
            var bytes = toByteArray(value: num1)
            bytes.append(contentsOf: toByteArray(value: num2))
            
            sendAsync(bytes: &bytes)
        }
        func sendEnded(socket: CSocket, error: CSocket.Error?) {
            readAsync(expectedLength: MemoryLayout<Int64>.size)
        }
        func readEnded(socket: CSocket, data: Data, error: CSocket.Error?) {
            if let error = error {
                self.asyncCallback?(self, 0, error)
            } else {
                let value = data.withUnsafeBytes { (p) -> Int64 in
                    return p.baseAddress!.load(as: Int64.self)
                }
                self.numbersMultiplied += 1
                self.asyncCallback?(self, value, nil)
            }
            
            
        }
        
    }

}

func toByteArray<T>(value: T) -> [UInt8] {
    var x = value
    return withUnsafeBytes(of: &x) { Array($0) }
}
func fromByteArray<T>(value: ArraySlice<UInt8>) -> T {
    
    return value.withUnsafeBytes {
        $0.baseAddress!.load(as: T.self)
    }
}
