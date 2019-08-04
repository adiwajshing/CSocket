# CSocket
## A very light, fully equiped, cross-platform & thread-safe pure swift TCP socket.

It is written using the IPV6 protocol (but it handles IPV4, don't worry) & non-blocking mode. CSocket can readily handle synchronous & asynchronous requests. The library is also very light, so don't worry about bulking up your project with this!

## Setup

### Option A:
Use Swift Package Manager, then just add the following line in your dependencies:

```swift

dependencies: [
    /* bla bla other dependencies */
    .package(url: "https://github.com/adiwajshing/CSocket.git", from: "1.0.0"),
    /* more dependencies */
]

```

And then add it to your target's dependencies like this:

```swift

.target(
    name: "MySPMProject",
    dependencies: ["CSocket", "AnotherDependency"]
)

```

### Option B:
If you're not using SPM, you can either compile a framework or copy and paste all the code into your project (it's not a lot of files), but you won't get updates with it and maintainance is a pain.


## Usage

### Creating an Instance

When you want to setup a listener:
```swift
let socket = CSocket(port: 8888) //the port you want to listen on
try socket.listen(maxBacklog: 128) // to start listening for incoming connections on '::/0' (IPV6 version of 0.0.0.0). Basically listens for connections from everywhere
```

When you want to use the socket to connect to a listener:
```swift
let socket = try CSocket(host: "www.google.com", port: 80) // the address is automatically looked up
print(socket.address) //looked up address (will not return "www.google.com")
```

### Calling Sync Operations

Accepting Connections:
```swift

while socket.isConnected {
if let socket = try socket.acceptAsync() {
print("yay \(socket) connected to this listener")
}
usleep(100 * 1000) //let the CPU rest for 100ms
}

```

Connecting:
```swift
socket.connectTimeout = 5.0 //set the timeout, set to -1 for infinite timeout
try socket.connectSync()
```

Sending:
```swift
let str = "my name jeff"
var data = Data(str.utf8) //get the utf8 data from the string

socket.sendTimeout = 5.0 //set the timeout, set to -1 for infinite timeout
try socket.sendSync(&data)
```

Reading:
```swift
socket.readTimeout = 5.0 //set the timeout, set to -1 for infinite timeout
let data = try socket.readSync(expectedLength: 12) //(12 is the length of "my name jeff")

let str = String(data: data, encoding: .utf8)
print(str)
```

Closing:

```swift
socket.close()
```

### Calling Async Operations

All asynchrous operations are handled via GCD.

First set up a delegate, derive your class from 'CSocketAsyncOperationsDelegate':

```swift

class SampleClass: CSocketAsyncOperationsDelegate {
    
    let socket: CSocket
    
    init () throws {
        socket = try CSocket(host: "127.0.0.1", port: 8888)
        socket.delegate = self //set the delegate to self
    }
}

```

Accepting Connections:
```swift

extension SampleClass {

    func listenAndAcceptClientsFromMySocket () {
        try! socket.listen(maxBacklog: 1024)
        socket.beginAcceptingLoop(intervalMS: 50) // the interval between which it will check for an incoming client, by default it is 100ms
    }

    // the callback event for when the listener accepts an incoming client
    func didAcceptClient (socket: CSocket) {
        print("yay, \(socket) connected to us")
        var data = Data("new connection who dis".utf8)
        socket.sendAsync(&data) //send a greeting
    }
}

```

Connecting:
```swift
extension SampleClass {

    func connectMySocket () {
        socket.connectTimeout = 4.0 // same timeout still applies
        socket.connectAsync()
    }
    
    // the callback event for when the socket connect attempt ends
    func connectEnded (socket: CSocket, error: CSocket.Error?) {
        if socket.isConnected {
            print("yay connected")
            
            /*
                start reading or send some data here
            */
            
        } else {
            print("connect failed with error: \(error!)")
        }
    }
}
```

Sending:
```swift
extension SampleClass {

    func sendSomeDataFromMySocket () {
        let str = "hello how are you"
        var data = Data(str.utf8) //get the utf8 data from the string
    
        socket.sendTimeout = 5.0 //set the timeout, set to -1 for infinite timeout
        socket.sendAsync(&data)
    }

    // the callback event for when the socket send attempt ends
    func sendEnded (socket: CSocket, error: CSocket.Error?) {
        if let error = error {
            print("send failed with error: \(error)")
        } else {
            print("yay, send success")
        }
    }
}
```

Reading:
```swift
extension SampleClass {

    func readDataSentToMySocket () {
        socket.readAsync(expectedLength: 128)
    }

    // the callback event for when the socket read attempt ends
    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?) {
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
Making a read loop:
You can make a loop either using a 'DispatchSourceTimer' or a 'DispatchSourceRead'.

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


#### Note: you only need a delegate for async operations, sync operations work fine without an async delegate. When a sync operation is called, its async callback will not be called. For eg.

```swift
extension SampleClass {

    func readDataSentToMySocketSync () {
        let data = try? socket.readSync(expectedLength: 128)
        /* 
            do something with data here
        */
    }

    func readEnded (socket: CSocket, data: Data, error: CSocket.Error?) {
        // will not be called
    }
}
```

## The properties
    
### Static properties with the default values. 
You don't really need to change any of the static properties unless you really want to fine tune.

```swift

//the dispatch queue which takes takes care of all async operations of all CSockets. Do not change this unless really required
public static var updateQueue = DispatchQueue(label: "c_socket_queue", qos: .default, attributes: [.concurrent], autoreleaseFrequency: .inherit, target: nil)

//the interval between checks for whether the socket has connected
public static var connectCheckIntervalMS = 100

//the interval between c send calls
public static var sendIntervalMS = 20

//the interval between each c recv calls
public static var readIntervalMS = 50 

```

### Local properties with the default values

```swift

//returns whether the socket is connected; just checks whether the socketfd is set or not
//to account for unexpected breaks in the connection, you'll have to write your own testConnection code
public var isConnected: Bool { get; }

public var description: String { get; }

//max timeout for connecting
public var connectTimeout = 5.0

//max timeout for sending a piece of data
public var sendTimeout = 5.0

//max timeout for reading some data
public var readTimeout = 5.0

// the minimum number of bytes required for the dataDidBecomeAvailable (socket:, bytes:) callback to be called. Setting it to 0 essentially makes an update loop when using DispatchSourceTimer for the read loop, which can also be useful 
public var readBytesThreshhold = 0

```

## Thread Safety

You can call all functions of CSocket & check connectivity without worrying about simultaneous accesses, bad accesses or any other thread related problems.
You can also simultaneously read & write to the same socket.
The thread safety is achieving using DispatchSemaphores.
However, I would recommend setting up the timeouts when creating the sockets as modifying those is thread-unsafe.

## Tests

CSocket has tests written for it, they're not very extensive though, but they do test concurrency & thread-safety quite well.

There is also a load test written -- 'CommunicationTests.swift' -- a client sends to numbers and the server returns the product.
This test also serves as a good example for how to use CSocket.
My MacBook Pro took only 40% CPU and about 25s to run a server and 1000 simultaneous clients with 2 async requests each -- which I believe is pretty good.

## Conclusion

I originally took inspiration from BlueSocket & ytcpsocket.c because they just wouldn't cut it for me.
ytcpsocket.c was written in C which made Linux use  difficult, whereas BlueSocket just seemed too bulky.

This is a library I wrote to use personally, but I believe a light socket library this functional can save a lot of developers a ton of time & headache.
The library is designed with server use in mind and hence, is made as light and efficient as possible. CSocket is very efficient in both sync & async operations. I've tried to balance CPU usage & speed as well as I could -- the checking intervals can be used to fine tune that further.

Moreover, the code is fully documented and I've tried to explain everything I've done in a way even someone just starting with sockets can understand.

Super open to criticism & possible improvements,
Adhiraj Singh
