//
//  NetworkAddress.swift
//  DistributedGRPCActorSystem
//
//  Created by Jonathan Holland on 12/10/25.
//

/// Represents a network address (host and port) for the actor system
public struct NetworkAddress: Sendable, Hashable, Codable {
	public let host: String
	public let port: Int

	public var endpoint: String { "\(host):\(port)" }

	public init(host: String, port: Int) {
		self.host = host
		self.port = port
	}

	public static func localhost(port: Int) -> NetworkAddress {
		NetworkAddress(host: "127.0.0.1", port: port)
	}
}
