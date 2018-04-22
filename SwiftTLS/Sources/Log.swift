//
//  Log.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 22.04.18.
//  Copyright © 2018 Nico Schmidt. All rights reserved.
//

import Foundation

class LoggingDateFormatter : DateFormatter
{
    override init()
    {
        super.init()
        dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

private var threadNumber = 0
private var threadNumberDict: [Thread:Int] = [:]
private let threadNumberQueue = DispatchQueue(label: "threadNumber")

extension Thread {
    var number: Int {
        var number = 0
        let thread = self
        threadNumberQueue.sync {
            if let n = threadNumberDict[thread] {
                number = n
                return
            }
            
            threadNumber += 1
            
            threadNumberDict[thread] = threadNumber
            
            number = threadNumber
        }
        
        return number
    }
    
    func removeThreadNumber() {
        let thread = self
        threadNumberQueue.async {
            threadNumberDict.removeValue(forKey: thread)
        }
    }
}

let threadNumberKey = DispatchSpecificKey<Int>()
class Log
{
    private var enabled: Bool = true
    private let formatter = LoggingDateFormatter()
    
    func log(_ message: @autoclosure () -> String, file: StaticString, line: UInt, time: Date) {
        if enabled {
            let threadNumber = Thread.current.number

            print("\(formatter.string(from: time)) (~\(threadNumber)): \(message())")
        }
    }
}

private let logger = Log()
public func log(_ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
    logger.log(message, file: file, line: line, time: Date())
}
