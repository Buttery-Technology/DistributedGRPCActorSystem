//
//  ExampleDistributedActor.swift
//  DistributedGRPCActorSystem
//
//  Example distributed actor demonstrating the GRPCActorSystem usage.
//

import Distributed
import Foundation

// MARK: - Example Distributed Actor

/// An example distributed actor that can be called remotely via gRPC.
///
/// ## Usage Example
/// ```swift
/// // Create the actor system
/// let system = GRPCActorSystem(node: .localhost(port: 8080))
/// try await system.start()
///
/// // Create a local actor
/// let greeter = Greeter(name: "World", actorSystem: system)
///
/// // Call the actor (works locally or remotely)
/// let greeting = try await greeter.greet()
/// print(greeting)  // "Hello, World!"
/// ```
public distributed actor Greeter {
    public typealias ActorSystem = GRPCActorSystem

    private let name: String

    public init(name: String, actorSystem: GRPCActorSystem) {
        self.actorSystem = actorSystem
        self.name = name
    }

    /// Returns a greeting message
    public distributed func greet() -> String {
        "Hello, \(name)!"
    }

    /// Returns a personalized greeting
    public distributed func greet(person: String) -> String {
        "Hello, \(person)! My name is \(name)."
    }

    /// Returns the actor's name
    public distributed func getName() -> String {
        name
    }
}

// MARK: - Counter Actor

/// A distributed counter actor demonstrating state management.
public distributed actor Counter {
    public typealias ActorSystem = GRPCActorSystem

    private var count: Int

    public init(initialValue: Int = 0, actorSystem: GRPCActorSystem) {
        self.actorSystem = actorSystem
        self.count = initialValue
    }

    /// Increment the counter and return the new value
    public distributed func increment() -> Int {
        count += 1
        return count
    }

    /// Decrement the counter and return the new value
    public distributed func decrement() -> Int {
        count -= 1
        return count
    }

    /// Get the current value
    public distributed func getValue() -> Int {
        count
    }

    /// Add a value and return the new total
    public distributed func add(_ value: Int) -> Int {
        count += value
        return count
    }
}

// MARK: - Calculator Actor

/// A distributed calculator actor demonstrating complex operations.
public distributed actor Calculator {
    public typealias ActorSystem = GRPCActorSystem

    private var memory: Double = 0

    public init(actorSystem: GRPCActorSystem) {
        self.actorSystem = actorSystem
    }

    /// Add two numbers
    public distributed func add(_ a: Double, _ b: Double) -> Double {
        a + b
    }

    /// Subtract b from a
    public distributed func subtract(_ a: Double, _ b: Double) -> Double {
        a - b
    }

    /// Multiply two numbers
    public distributed func multiply(_ a: Double, _ b: Double) -> Double {
        a * b
    }

    /// Divide a by b
    public distributed func divide(_ a: Double, _ b: Double) throws -> Double {
        guard b != 0 else {
            throw CalculatorError.divisionByZero
        }
        return a / b
    }

    /// Store a value in memory
    public distributed func store(_ value: Double) {
        memory = value
    }

    /// Recall the stored value
    public distributed func recall() -> Double {
        memory
    }

    /// Clear memory
    public distributed func clearMemory() {
        memory = 0
    }
}

/// Calculator errors
public enum CalculatorError: Error, Codable {
    case divisionByZero
}

// MARK: - Node Information Actor

/// A distributed actor that provides information about its host node.
public distributed actor NodeInfoActor {
    public typealias ActorSystem = GRPCActorSystem

    public let nodeId: String
    public let startTime: Date

    public init(nodeId: String, actorSystem: GRPCActorSystem) {
        self.actorSystem = actorSystem
        self.nodeId = nodeId
        self.startTime = Date()
    }

    /// Get the node's identifier
    public distributed func getNodeId() -> String {
        nodeId
    }

    /// Get the node's start time
    public distributed func getStartTime() -> Date {
        startTime
    }

    /// Get the node's uptime in seconds
    public distributed func getUptime() -> TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Get node status
    public distributed func getStatus() -> NodeStatus {
        NodeStatus(
            nodeId: nodeId,
            startTime: startTime,
            uptime: getUptime(),
            isHealthy: true
        )
    }
}

/// Node status information
public struct NodeStatus: Codable, Sendable {
    public let nodeId: String
    public let startTime: Date
    public let uptime: TimeInterval
    public let isHealthy: Bool
}
