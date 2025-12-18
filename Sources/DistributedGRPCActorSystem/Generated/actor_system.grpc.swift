//
//  actor_system.grpc.swift
//  DistributedGRPCActorSystem
//
//  Hand-written gRPC service definitions following grpc-swift-2 patterns
//

import Foundation
import GRPCCore
import NIOCore

// MARK: - Service Descriptor

public enum Distributed_actor_system_ActorSystemService {
    public static let descriptor = GRPCCore.ServiceDescriptor(
        fullyQualifiedService: "distributed_actor_system.ActorSystemService"
    )

    public enum Method {
        public enum Invoke {
            public typealias Input = Distributed_actor_system_InvocationRequest
            public typealias Output = Distributed_actor_system_InvocationResponse
            public static let descriptor = GRPCCore.MethodDescriptor(
                service: GRPCCore.ServiceDescriptor(
                    fullyQualifiedService: "distributed_actor_system.ActorSystemService"
                ),
                method: "Invoke"
            )
        }

        public enum RegisterActor {
            public typealias Input = Distributed_actor_system_RegisterActorRequest
            public typealias Output = Distributed_actor_system_RegisterActorResponse
            public static let descriptor = GRPCCore.MethodDescriptor(
                service: GRPCCore.ServiceDescriptor(
                    fullyQualifiedService: "distributed_actor_system.ActorSystemService"
                ),
                method: "RegisterActor"
            )
        }

        public enum Ping {
            public typealias Input = Distributed_actor_system_PingRequest
            public typealias Output = Distributed_actor_system_PingResponse
            public static let descriptor = GRPCCore.MethodDescriptor(
                service: GRPCCore.ServiceDescriptor(
                    fullyQualifiedService: "distributed_actor_system.ActorSystemService"
                ),
                method: "Ping"
            )
        }

        public static let descriptors: [GRPCCore.MethodDescriptor] = [
            Invoke.descriptor,
            RegisterActor.descriptor,
            Ping.descriptor
        ]
    }
}

// MARK: - Service Protocol

extension Distributed_actor_system_ActorSystemService {
    public protocol StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
        func invoke(
            request: GRPCCore.StreamingServerRequest<Distributed_actor_system_InvocationRequest>,
            context: GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_InvocationResponse>

        func registerActor(
            request: GRPCCore.StreamingServerRequest<Distributed_actor_system_RegisterActorRequest>,
            context: GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_RegisterActorResponse>

        func ping(
            request: GRPCCore.StreamingServerRequest<Distributed_actor_system_PingRequest>,
            context: GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_PingResponse>
    }

    public protocol SimpleServiceProtocol: StreamingServiceProtocol {
        func invoke(
            request: Distributed_actor_system_InvocationRequest,
            context: GRPCCore.ServerContext
        ) async throws -> Distributed_actor_system_InvocationResponse

        func registerActor(
            request: Distributed_actor_system_RegisterActorRequest,
            context: GRPCCore.ServerContext
        ) async throws -> Distributed_actor_system_RegisterActorResponse

        func ping(
            request: Distributed_actor_system_PingRequest,
            context: GRPCCore.ServerContext
        ) async throws -> Distributed_actor_system_PingResponse
    }
}

// MARK: - Register Methods Implementation

extension Distributed_actor_system_ActorSystemService.StreamingServiceProtocol {
    public func registerMethods<Transport>(
        with router: inout GRPCCore.RPCRouter<Transport>
    ) where Transport: GRPCCore.ServerTransport {
        router.registerHandler(
            forMethod: Distributed_actor_system_ActorSystemService.Method.Invoke.descriptor,
            deserializer: JSONMessageDeserializer<Distributed_actor_system_InvocationRequest>(),
            serializer: JSONMessageSerializer<Distributed_actor_system_InvocationResponse>(),
            handler: { request, context in
                try await self.invoke(request: request, context: context)
            }
        )

        router.registerHandler(
            forMethod: Distributed_actor_system_ActorSystemService.Method.RegisterActor.descriptor,
            deserializer: JSONMessageDeserializer<Distributed_actor_system_RegisterActorRequest>(),
            serializer: JSONMessageSerializer<Distributed_actor_system_RegisterActorResponse>(),
            handler: { request, context in
                try await self.registerActor(request: request, context: context)
            }
        )

        router.registerHandler(
            forMethod: Distributed_actor_system_ActorSystemService.Method.Ping.descriptor,
            deserializer: JSONMessageDeserializer<Distributed_actor_system_PingRequest>(),
            serializer: JSONMessageSerializer<Distributed_actor_system_PingResponse>(),
            handler: { request, context in
                try await self.ping(request: request, context: context)
            }
        )
    }
}

// MARK: - Default Streaming Implementations

extension Distributed_actor_system_ActorSystemService.SimpleServiceProtocol {
    public func invoke(
        request: GRPCCore.StreamingServerRequest<Distributed_actor_system_InvocationRequest>,
        context: GRPCCore.ServerContext
    ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_InvocationResponse> {
        let serverRequest = try await GRPCCore.ServerRequest(stream: request)
        let response = try await self.invoke(request: serverRequest.message, context: context)
        return GRPCCore.StreamingServerResponse(
            single: GRPCCore.ServerResponse(message: response, metadata: [:])
        )
    }

    public func registerActor(
        request: GRPCCore.StreamingServerRequest<Distributed_actor_system_RegisterActorRequest>,
        context: GRPCCore.ServerContext
    ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_RegisterActorResponse> {
        let serverRequest = try await GRPCCore.ServerRequest(stream: request)
        let response = try await self.registerActor(request: serverRequest.message, context: context)
        return GRPCCore.StreamingServerResponse(
            single: GRPCCore.ServerResponse(message: response, metadata: [:])
        )
    }

    public func ping(
        request: GRPCCore.StreamingServerRequest<Distributed_actor_system_PingRequest>,
        context: GRPCCore.ServerContext
    ) async throws -> GRPCCore.StreamingServerResponse<Distributed_actor_system_PingResponse> {
        let serverRequest = try await GRPCCore.ServerRequest(stream: request)
        let response = try await self.ping(request: serverRequest.message, context: context)
        return GRPCCore.StreamingServerResponse(
            single: GRPCCore.ServerResponse(message: response, metadata: [:])
        )
    }
}

// MARK: - Client

extension Distributed_actor_system_ActorSystemService {
    public struct Client<Transport: ClientTransport>: Sendable {
        private let client: GRPCCore.GRPCClient<Transport>

        public init(wrapping client: GRPCCore.GRPCClient<Transport>) {
            self.client = client
        }

        public func invoke(
            _ request: Distributed_actor_system_InvocationRequest,
            metadata: Metadata = [:]
        ) async throws -> Distributed_actor_system_InvocationResponse {
            try await client.unary(
                request: ClientRequest(message: request, metadata: metadata),
                descriptor: Method.Invoke.descriptor,
                serializer: JSONMessageSerializer<Method.Invoke.Input>(),
                deserializer: JSONMessageDeserializer<Method.Invoke.Output>(),
                options: .defaults
            ) { response in
                try response.message
            }
        }

        public func registerActor(
            _ request: Distributed_actor_system_RegisterActorRequest,
            metadata: Metadata = [:]
        ) async throws -> Distributed_actor_system_RegisterActorResponse {
            try await client.unary(
                request: ClientRequest(message: request, metadata: metadata),
                descriptor: Method.RegisterActor.descriptor,
                serializer: JSONMessageSerializer<Method.RegisterActor.Input>(),
                deserializer: JSONMessageDeserializer<Method.RegisterActor.Output>(),
                options: .defaults
            ) { response in
                try response.message
            }
        }

        public func ping(
            _ request: Distributed_actor_system_PingRequest,
            metadata: Metadata = [:]
        ) async throws -> Distributed_actor_system_PingResponse {
            try await client.unary(
                request: ClientRequest(message: request, metadata: metadata),
                descriptor: Method.Ping.descriptor,
                serializer: JSONMessageSerializer<Method.Ping.Input>(),
                deserializer: JSONMessageDeserializer<Method.Ping.Output>(),
                options: .defaults
            ) { response in
                try response.message
            }
        }
    }
}

// MARK: - JSON Serialization

public struct JSONMessageSerializer<Message: Codable & Sendable>: GRPCCore.MessageSerializer, Sendable {
    public init() {}

    public func serialize<Bytes: GRPCContiguousBytes>(_ message: Message) throws -> Bytes {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)
        return Bytes(data)
    }
}

public struct JSONMessageDeserializer<Message: Codable & Sendable>: GRPCCore.MessageDeserializer, Sendable {
    public init() {}

    public func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> Message {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = serializedMessageBytes.withUnsafeBytes { Data($0) }
        return try decoder.decode(Message.self, from: data)
    }
}
