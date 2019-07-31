//
//  AtomicValue.swift
//  MySQL
//
//  Created by Adhiraj Singh on 7/28/19.
//

import Foundation

public class AtomicValue <T> {
    
    private var value: T
    private let sm = DispatchSemaphore(value: 1)
    
    public init (_ value: T) {
        self.value = value
    }
    
    public func access () {
        sm.wait()
    }
    
    public func release () {
        sm.signal()
    }
    
    public func work (_ operation: ((inout T) -> Void)) {
        defer {
            self.release()
        }
        
        self.access()
        operation(&value)
    }
    
    public func get () -> T {
        defer {
            self.release()
        }
        self.access()
        let v = value
        return v
    }
    public func set (_ newValue: T) {
        defer {
            self.release()
        }
        self.access()
        value = newValue
    }
}
public class ISemaphore {
    
    private let sm = DispatchSemaphore(value: 1)
    private let counter = AtomicValue<UInt8>(0)
    
    public func wait () {
        counter.work { (value) in
            value += 1
        }
        sm.wait()
    }
    public func signal () {
        
        counter.work { (value) in
            value -= 1
        }
        
        sm.signal()
        
    }
    
    public func accessorCount () -> Int {
        return Int(counter.get())
    }
}
