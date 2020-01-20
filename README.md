# CSocket
## A very light, cross-platform, fully asynchronous, event-driven & thread-safe pure swift TCP socket.

The library is written entirely in the IPV6 protocol (but it handles IPV4, don't worry) & uses non-blocking C sockets.
The library is also very light, so don't worry about bulking up your project with this!

## Setup

### Option A:
Use Swift Package Manager, then just add the following line in your dependencies:

```swift

dependencies: [
    /* bla bla other dependencies */
    .package(url: "https://github.com/adiwajshing/CSocket.git", from: "2.0.0"), // (Add this line)
    /* more dependencies */
],
targets: [
    .target(
        name: "MySPMProject",
        dependencies: ["CSocket", "AnotherDependency", "MoreDependency"] // And add it as a dependency
    )
    /* more targets */
]

```

### Option B:
If you're not using SPM, you can either compile a framework or copy and paste all the code into your project (it's not a lot of files), but you won't get updates with it and maintainance is a pain.

## Before you start
The library is completely asynchronous and is uses Google's Promises to make asynchronous operations really simple to handle. The library uses DispatchSourceRead and DispatchSourceWrite to notify when data is available to read, an incoming connection is present, or data is available to write etc. DispatchSourceTimer is used to manage timeouts.

## Usage

### Creating an Instance

When you want to setup a listener that will accept incoming connections:
```swift
let socket = CSocket(port: 8888) //the port you want to listen on, will setup the connection on '::/0' (IPV6 version of 0.0.0.0). Basically listens for connections from everywhere
try socket.listen(maxBacklog: 128) // to start listening for incoming connections
```

When you want to use the socket to connect to a listener:
```swift
let socket = try CSocket(host: "www.google.com", port: 80) // the address is automatically looked up via the system DNS
print(socket.address) //looked up address (will not return "www.google.com")

// or if you don't want the address to be parsed by the DNS
let socket = CSocket(address: "localhost", port: 8888)
```

### Calling Operations

Accepting Connections:
```swift

let socket = CSocket(port: 8888) //the port you want to listen on
try socket.listen(maxBacklog: 128) // start listening for incoming connections
try socket.beginAcceptingLoop { result in
    switch result {
    case .success(let client):
        print("connected: \(client.description)")
        /* Read from client or send some data etc. */
        break
    case .failure(let error):
        print("error in accepting: \(error)")
        socket.close() // close the socket because of the error :/
        break
    }
}

```

Connecting:
```swift
let socket = CSocket(address: "localhost", port: 8888)
_ = socket.connect(timeout: .seconds(5))
.then { print("yay connected") }
.catch { error in print("oh no there was an error in connecting: \(error)") }
```

Sending data:
```swift
let str = "my name jeff"
let data = Data(str.utf8) //get the utf8 data from the string

_ = socket.send(data: data, timeout: .seconds(5))
.then { print("yay data sent") }
.then { /* do some other work */ }
.then { /* maybe read from the socket */ }
.catch { error in print("oh no there was an error in sending data: \(error)") }
```

Reading data:
```swift

_ = socket.read(expectedCount: 12, timeout: .never) //(12 is the length of "my name jeff")
.then { data in
    let str = String(data: data, encoding: .utf8)
    print("got data: \(str)")
}
.catch { error in print("oh no there was an error in reading data: \(error)") }

```

Closing:

```swift
socket.close()
```
Making a read loop:

```swift
extension SampleClass {

    func makeReadLoopForMySocket () {
        socket.readBytesThreshhold = 16 // the minimum number of bytes required for the callback to be called
        socket.notifyOnDataAvailable (useDispatchSourceRead: false, intervalMS: 100) // the interval between which it will check for an available data
    }
    
    // the callback event for when the socket has data available to read
    func dataDidBecomeAvailable (socket: CSocket, bytes: Int) {
        socket.readAsync (expectedLength: bytes) // the timer is paused once a read is called
    }
    // the callback event for when the socket read attempt ends
    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?) {
        // the timer is resumed once a read is finished
        
        if let error = error {
            print ("read failed with error: \(error)")
        } else {
            /*
            do something with the data recieved here
            */
        }
    }
}
```
Working synchronously with CSocket:

```swift
import Promises // include the promises library
// call the await() function on any CSocket function to wait for it to complete synchronously

try await ( socket.connect(timeout: .seconds(5)) ) // wait for the socket connection to complete

try await ( socket.send(data: data, timeout: .seconds(5)) ) // wait for the socket to send all the data

let data = try await ( socket.read(expectedCount: count, timeout: .seconds(5)) ) // wait for the socket read to complete
print("got data from read: \(data)")
```

## The properties
    
### Local properties with the default values

```swift

//returns whether the socket is connected; just checks whether the socketfd is set or not
//to account for unexpected breaks in the connection, you'll have to write your own testConnection code
public var isConnected: Bool { get; }
//just prints 'address:port (socket file descriptor)'
public var description: String { get; }

```

## Thread Safety

You can call all functions of CSocket & check connectivity without worrying about simultaneous accesses, bad accesses or any other thread related problems.
You can also simultaneously read & write to the same socket.
The thread safety is achieving using DispatchSemaphores.
However, I would recommend setting up the timeouts when creating the sockets as modifying those is thread-unsafe.

## Tests

CSocket has tests written for it, they're not very extensive though, but they do test concurrency & thread-safety quite well.

There is also a load test written -- 'CommunicationTests.swift' -- a client sends two numbers and the server returns the product of the numbers. This test also serves as a good example for how to use CSocket.
A MacBook Pro takes about 500% CPU and about 9s to run a server and 5000 simultaneous clients with 10 simple requests each.

## Conclusion

I originally took inspiration from BlueSocket & ytcpsocket.c because they just wouldn't cut it for me.
ytcpsocket.c was written in C which made Linux use a pain, whereas BlueSocket just seemed too bulky.

This is a library I wrote to use personally, but I believe a light, event-driven socket library can save developers a ton of time. The library is designed with server use in mind and hence, is made as light and efficient as possible.

Moreover, the code is fully documented and I've tried to explain everything I've done in a way even someone just beginning with sockets can understand.

Super open to criticism & possible improvements,
Adhiraj Singh
