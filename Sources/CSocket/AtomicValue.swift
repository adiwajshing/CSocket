//
//  AtomicValue.swift
//  CSocket
//
//  Created by Adhiraj Singh on 7/28/19.
//

import Foundation

///Thread Safe Object
public class AtomicValue <T> {
    
    private var value: T
    private let sm = DispatchSemaphore(value: 1)
    
    public init (_ value: T) {
        self.value = value
    }
    
    public func work (_ operation: ((inout T) -> Void)) {
        defer {
            sm.signal()
        }
        
        sm.wait()
        operation(&value)
    }
    
    public func get () -> T {
        defer {
            sm.signal()
        }
        sm.wait()
        let v = value
        return v
    }
    public func set (_ newValue: T) {
        self.work { (oValue) in
            oValue = newValue
        }
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
