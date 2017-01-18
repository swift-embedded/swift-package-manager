/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch
import Foundation
import Basic

typealias Thread = Basic.Thread

public enum ProcessSetError: Swift.Error {
    /// The process group was cancelled and doesn't allow adding more processes.
    case cancelled
}

/// A process set is a small wrapper for collection of processes.
/// 
/// This class is thread safe.
public final class ProcessSet {

    /// Array to hold the processes.
    private var processes: Set<Process> = []

    /// Queue to mutate internal states of the process group.
    private let serialQueue = DispatchQueue(label: "org.swift.swiftpm.process-set")

    /// If the process group was asked to cancel all active processes.
    private var cancelled = false

    /// The timeout (in seconds) after which the processes should be killed if they don't respond to SIGINT.
    public let killTimeout: Double

    /// Condition to block kill thread until timeout.
    private var killingCondition = Condition()

    /// Boolean predicate for killing condition.
    private var shouldKill = false

    /// Create a process set.
    public init(killTimeout: Double = 5) {
        self.killTimeout = killTimeout
    }

    /// Add a process to the process set. This method will throw if the process set is terminated using the terminate() method.
    ///
    /// Call remove() method to remove the process from set once it has terminated.
    ///
    /// - Parameters:
    ///   - process: The process to add.
    /// - Throws: ProcessGroupError
    public func add(_ process: Process) throws {
        return try serialQueue.sync {
            guard !cancelled else {
                throw ProcessSetError.cancelled
            }
            self.processes.insert(process)
        }
    }

    /// Remove the process from process set.
    public func remove(_ process: Process) {
        serialQueue.sync {
            self.processes.remove(process) 
            // If all processes terminated and we're cancelled, unblock the killing thread.
            if cancelled && self.processes.isEmpty {
                killingCondition.whileLocked {
                    shouldKill = true
                    killingCondition.signal()
                }
            }
        }
    }

    /// Terminate all the processes. This method blocks until all processes in the set are terminated.
    ///
    /// A process set cannot be used once it has been asked to terminate.
    public func terminate() {
        // Mark as process set as cancelled.
        serialQueue.sync {
            cancelled = true
        }

        // Interrupt all processes.
        signalAll(SIGINT)

        // Create a thread that will kill all processes after a timeout.
        let thread = Basic.Thread {
            // Compute the timeout date.
            let timeout = Date() + self.killTimeout
            // Block until we timeout or notification.
            self.killingCondition.whileLocked {
                while !self.shouldKill {
                    // Block until timeout expires.
                    let timeLimitReached = !self.killingCondition.wait(until: timeout)
                    // Set should kill to true if time limit was reached.
                    if timeLimitReached {
                        self.shouldKill = true
                    }
                }
            }
            // Send kill signal to all processes.
            self.signalAll(SIGKILL)
        }

        thread.start()
        // FIXME: If Process class was thread safe, we could call waitUntilExit() here
        // and then we wouldn't need clients to call remove() method to indicate
        // that the process has terminated. This would be a nice thing to eventually add.
        thread.join()
    }

    /// Sends signal to all processes in the set.
    private func signalAll(_ signal: Int32) {
        serialQueue.sync {
            // Signal all active processes.
            for process in self.processes where process.result == nil {
                process.signal(signal)
            }
        }
    }
}