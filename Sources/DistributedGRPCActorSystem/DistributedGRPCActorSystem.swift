//
//  GRPCActorSystem.swift
//  DistributedGRPCActorSystem
//
//  A distributed actor system using gRPC for remote communication.
//

import Distributed
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import Logging
import NIOCore
import NIOPosix

// MARK: - Actor Registry

/// Thread-safe actor registry using an actor
actor ActorRegistry {
    private var actors: [ActorIdentity: any DistributedActor] = [:]

    func register(_ actor: any DistributedActor, with id: ActorIdentity) {
        actors[id] = actor
    }

    func unregister(_ id: ActorIdentity) {
        actors.removeValue(forKey: id)
    }

    func get(_ id: ActorIdentity) -> (any DistributedActor)? {
        actors[id]
    }

    func contains(_ id: ActorIdentity) -> Bool {
        actors[id] != nil
    }
}

/// Thread-safe client registry
actor ClientRegistry {
    private var clients: [NetworkAddress: GRPCClient<HTTP2ClientTransport.Posix>] = [:]

    func get(_ node: NetworkAddress) -> GRPCClient<HTTP2ClientTransport.Posix>? {
        clients[node]
    }

    func set(_ client: GRPCClient<HTTP2ClientTransport.Posix>, for node: NetworkAddress) {
        clients[node] = client
    }

    func shutdownAll() {
        for (_, client) in clients {
            client.beginGracefulShutdown()
        }
        clients.removeAll()
    }
}

// MARK: - GRPCActorSystem

/// A distributed actor system that uses gRPC for remote communication.
public final class GRPCActorSystem: DistributedActorSystem, @unchecked Sendable {
    public typealias ActorID = ActorIdentity
    public typealias InvocationEncoder = GRPCInvocationEncoder
    public typealias InvocationDecoder = GRPCInvocationDecoder
    public typealias SerializationRequirement = Codable
    public typealias ResultHandler = GRPCResultHandler

    /// The network address this actor system listens on
    public let address: NetworkAddress

    /// Logger for this actor system
    private let logger: Logger

    /// Registry of local actors
    private let actorRegistry = ActorRegistry()

    /// Registry of gRPC clients to remote addresses
    private let clientRegistry = ClientRegistry()

    /// gRPC server for receiving remote calls
    private var server: GRPCServer<HTTP2ServerTransport.Posix>?

    /// Default timeout for remote calls in seconds
    public var defaultTimeout: TimeInterval = 30.0

    /// Whether the system is running
    public private(set) var isRunning: Bool = false

    /// Create a new gRPC actor system
    public init(address: NetworkAddress, logger: Logger? = nil) {
        self.address = address
        self.logger = logger ?? Logger(label: "GRPCActorSystem.\(address.endpoint)")
    }

    // MARK: - Lifecycle

    /// Start the actor system
    public func start() async throws {
        guard !isRunning else {
            logger.warning("Actor system already running")
            return
        }

        logger.info("Starting GRPCActorSystem on \(address.endpoint)")

        let service = ActorSystemGRPCService(actorSystem: self)
        server = GRPCServer(
            transport: .http2NIOPosix(
                address: .ipv4(host: address.host, port: address.port),
                transportSecurity: .plaintext,
                config: .defaults()
            ),
            services: [service]
        )

        isRunning = true
        logger.info("GRPCActorSystem started on \(address.endpoint)")
    }

    /// Run the gRPC server (blocking)
    public func run() async throws {
        guard let server else {
            throw DistributedActorSystemError.invocationFailed("Server not started")
        }
        try await server.serve()
    }

    /// Stop the actor system
    public func shutdown() async {
        logger.info("Shutting down GRPCActorSystem")
        await clientRegistry.shutdownAll()
        isRunning = false
        logger.info("GRPCActorSystem shutdown complete")
    }

    // MARK: - DistributedActorSystem Protocol

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        // For remote actors, return nil to trigger remoteCall
        if id.address != address {
            return nil
        }

        // Note: We can't call async from this sync context, so we return nil
        // The actual resolution happens in the async call paths
        return nil
    }

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
        where Act: DistributedActor
    {
        let id = ActorIdentity(
            id: UUID().uuidString,
            typeName: String(describing: actorType),
            address: address
        )
        logger.debug("Assigned ID: \(id)")
        return id
    }

    public func actorReady<Act>(_ actor: Act)
        where Act: DistributedActor, Act.ID == ActorID
    {
        Task {
            await actorRegistry.register(actor, with: actor.id)
            logger.debug("Actor ready: \(actor.id)")
        }
    }

    public func resignID(_ id: ActorID) {
        Task {
            await actorRegistry.unregister(id)
            logger.debug("Actor resigned: \(id)")
        }
    }

    public func makeInvocationEncoder() -> InvocationEncoder {
        GRPCInvocationEncoder()
    }

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
        where Act: DistributedActor,
              Act.ID == ActorID,
              Err: Error,
              Res: SerializationRequirement
    {
        let actorID = actor.id

        // Check if this is a local actor
        if actorID.address == address {
            if let localActor = await actorRegistry.get(actorID) {
                var decoder = GRPCInvocationDecoder(data: invocation.encode())
                let handler = GRPCResultHandler()

                try await executeDistributedTarget(
                    on: localActor,
                    target: target,
                    invocationDecoder: &decoder,
                    handler: handler
                )

                guard let resultData = handler.resultData else {
                    throw DistributedActorSystemError.invocationFailed("No result returned")
                }

                let jsonDecoder = JSONDecoder()
                jsonDecoder.dateDecodingStrategy = .iso8601
                return try jsonDecoder.decode(Res.self, from: resultData)
            }
            throw DistributedActorSystemError.actorNotFound(actorID)
        }

        // Execute remote call
        let responseData = try await executeRemoteCall(
            actorID: actorID,
            target: target,
            invocation: &invocation
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Res.self, from: responseData)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
        where Act: DistributedActor,
              Act.ID == ActorID,
              Err: Error
    {
        let actorID = actor.id

        if actorID.address == address {
            if let localActor = await actorRegistry.get(actorID) {
                var decoder = GRPCInvocationDecoder(data: invocation.encode())
                let handler = GRPCResultHandler()

                try await executeDistributedTarget(
                    on: localActor,
                    target: target,
                    invocationDecoder: &decoder,
                    handler: handler
                )
                return
            }
            throw DistributedActorSystemError.actorNotFound(actorID)
        }

        _ = try await executeRemoteCall(
            actorID: actorID,
            target: target,
            invocation: &invocation
        )
    }

    // MARK: - Remote Call Execution

    private func executeRemoteCall(
        actorID: ActorID,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder
    ) async throws -> Data {
        let callID = UUID().uuidString
        let targetAddress = actorID.address

        logger.debug("Executing remote call \(callID) to \(actorID) method: \(target.identifier)")

        let request = Distributed_actor_system_InvocationRequest.with {
            $0.callID = callID
            $0.target = actorID.toProto()
            $0.methodName = target.identifier
            $0.arguments = invocation.encode()
            $0.genericSubstitutions = invocation.genericSubstitutions
            $0.timeoutMs = Int64(defaultTimeout * 1000)
        }

        let client = try await getOrCreateClient(for: targetAddress)
        let service = Distributed_actor_system_ActorSystemService.Client(wrapping: client)
        let response = try await service.invoke(request)

        if response.success {
            return response.result
        } else {
            throw DistributedActorSystemError.invocationFailed(response.error.message)
        }
    }

    private func getOrCreateClient(for targetNode: NetworkAddress) async throws -> GRPCClient<HTTP2ClientTransport.Posix> {
        if let existing = await clientRegistry.get(targetNode) {
            return existing
        }

        let client = try GRPCClient(
            transport: .http2NIOPosix(
                target: .ipv4(address: targetNode.host, port: targetNode.port),
                transportSecurity: .plaintext
            )
        )

        // Start client connection in background
        Task {
            do {
                try await client.runConnections()
            } catch {
                logger.error("Client connection error for \(targetNode.endpoint): \(error)")
            }
        }

        await clientRegistry.set(client, for: targetNode)
        return client
    }

    // MARK: - Incoming Call Handling

    func handleIncomingInvocation(
        _ request: Distributed_actor_system_InvocationRequest
    ) async -> Distributed_actor_system_InvocationResponse {
        let actorID = ActorIdentity.fromProto(request.target)

        logger.debug("Handling incoming call \(request.callID) to \(actorID)")

        guard let actor = await actorRegistry.get(actorID) else {
            return Distributed_actor_system_InvocationResponse.with {
                $0.callID = request.callID
                $0.success = false
                $0.error = Distributed_actor_system_ErrorInfo.with {
                    $0.code = "ACTOR_NOT_FOUND"
                    $0.message = "Actor not found: \(actorID)"
                }
            }
        }

        do {
            var decoder = GRPCInvocationDecoder(data: request.arguments)
            let handler = GRPCResultHandler()

            let target = RemoteCallTarget(request.methodName)
            try await executeDistributedTarget(
                on: actor,
                target: target,
                invocationDecoder: &decoder,
                handler: handler
            )

            return Distributed_actor_system_InvocationResponse.with {
                $0.callID = request.callID
                $0.success = true
                $0.result = handler.resultData ?? Data()
            }
        } catch {
            logger.error("Invocation failed: \(error)")
            return Distributed_actor_system_InvocationResponse.with {
                $0.callID = request.callID
                $0.success = false
                $0.error = Distributed_actor_system_ErrorInfo.with {
                    $0.code = "INVOCATION_FAILED"
                    $0.message = String(describing: error)
                }
            }
        }
    }
}

// MARK: - Proto Conversion Extensions

extension ActorIdentity {
    func toProto() -> Distributed_actor_system_ActorIdentity {
        Distributed_actor_system_ActorIdentity.with {
            $0.id = id
            $0.typeName = typeName
            $0.nodeHost = address.host
            $0.nodePort = Int32(address.port)
            $0.metadata = metadata
        }
    }

    static func fromProto(_ proto: Distributed_actor_system_ActorIdentity) -> ActorIdentity {
        ActorIdentity(
            id: proto.id,
            typeName: proto.typeName,
            address: NetworkAddress(host: proto.nodeHost, port: Int(proto.nodePort)),
            metadata: proto.metadata
        )
    }
}
