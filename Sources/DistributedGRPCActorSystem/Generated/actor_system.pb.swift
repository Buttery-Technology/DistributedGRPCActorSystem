//
//  actor_system.pb.swift
//  DistributedGRPCActorSystem
//
//  Hand-written protobuf message definitions
//  (equivalent to generated code from actor_system.proto)
//

import Foundation

// MARK: - ActorIdentity Message

/// Protobuf message for actor identity
public struct Distributed_actor_system_ActorIdentity: Sendable, Hashable, Codable {
    public var id: String = ""
    public var typeName: String = ""
    public var nodeHost: String = ""
    public var nodePort: Int32 = 0
    public var metadata: [String: String] = [:]

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - InvocationRequest Message

/// Protobuf message for method invocation request
public struct Distributed_actor_system_InvocationRequest: Sendable, Codable {
    public var callID: String = ""
    public var target: Distributed_actor_system_ActorIdentity = .init()
    public var methodName: String = ""
    public var arguments: Data = Data()
    public var genericSubstitutions: [String] = []
    public var timeoutMs: Int64 = 0
    public var caller: Distributed_actor_system_ActorIdentity = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - InvocationResponse Message

/// Protobuf message for method invocation response
public struct Distributed_actor_system_InvocationResponse: Sendable, Codable {
    public var callID: String = ""
    public var success: Bool = false
    public var result: Data = Data()
    public var error: Distributed_actor_system_ErrorInfo = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - ErrorInfo Message

/// Protobuf message for error information
public struct Distributed_actor_system_ErrorInfo: Sendable, Codable {
    public var code: String = ""
    public var message: String = ""
    public var details: String = ""

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - RegisterActorRequest Message

public struct Distributed_actor_system_RegisterActorRequest: Sendable, Codable {
    public var identity: Distributed_actor_system_ActorIdentity = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - RegisterActorResponse Message

public struct Distributed_actor_system_RegisterActorResponse: Sendable, Codable {
    public var success: Bool = false
    public var message: String = ""

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - UnregisterActorRequest Message

public struct Distributed_actor_system_UnregisterActorRequest: Sendable, Codable {
    public var identity: Distributed_actor_system_ActorIdentity = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - UnregisterActorResponse Message

public struct Distributed_actor_system_UnregisterActorResponse: Sendable, Codable {
    public var success: Bool = false

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - ResolveActorRequest Message

public struct Distributed_actor_system_ResolveActorRequest: Sendable, Codable {
    public var identity: Distributed_actor_system_ActorIdentity = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - ResolveActorResponse Message

public struct Distributed_actor_system_ResolveActorResponse: Sendable, Codable {
    public var exists: Bool = false
    public var resolvedIdentity: Distributed_actor_system_ActorIdentity = .init()

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - PingRequest Message

public struct Distributed_actor_system_PingRequest: Sendable, Codable {
    public var nodeHost: String = ""
    public var nodePort: Int32 = 0

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}

// MARK: - PingResponse Message

public struct Distributed_actor_system_PingResponse: Sendable, Codable {
    public var alive: Bool = false
    public var timestamp: Int64 = 0

    public init() {}

    public static func with(_ configure: (inout Self) -> Void) -> Self {
        var message = Self()
        configure(&message)
        return message
    }
}
