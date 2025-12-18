//
//  ActorIdentity.swift
//  DistributedGRPCActorSystem
//
//  Created by Jonathan Holland on 12/10/25.
//

// Unique identity for distributed actors across the cluster

import Foundation

/// Uniquely identifies a distributed actor across the cluster
public struct ActorIdentity: Sendable, Hashable, Codable {
    /// The unique identifier for this actor instance
    public let id: String
    
    /// The type name of the actor (used for resolution)
    public let typeName: String
    
    /// The network address where this actor resides
    public let address: NetworkAddress
    
    /// Optional metadata for routing or sharding
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        typeName: String,
        address: NetworkAddress,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.typeName = typeName
        self.address = address
        self.metadata = metadata
    }
    
    /// Creates a local actor identity on the given address
    public static func local(typeName: String, on address: NetworkAddress) -> ActorIdentity {
        ActorIdentity(typeName: typeName, address: address)
    }
}

extension ActorIdentity: CustomStringConvertible {
    public var description: String {
        "\(typeName)@\(address.endpoint)/\(id)"
    }
}
