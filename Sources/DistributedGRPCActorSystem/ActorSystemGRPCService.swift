//
//  ActorSystemGRPCService.swift
//  DistributedGRPCActorSystem
//
//  gRPC service implementation for distributed actor invocations
//

import Foundation
import GRPCCore
import Logging

/// gRPC service implementation for handling distributed actor invocations
final class ActorSystemGRPCService: Distributed_actor_system_ActorSystemService.SimpleServiceProtocol, Sendable {
    private let actorSystem: GRPCActorSystem
    private let logger: Logger

    init(actorSystem: GRPCActorSystem) {
        self.actorSystem = actorSystem
        self.logger = Logger(label: "ActorSystemGRPCService.\(actorSystem.address.endpoint)")
    }

    // MARK: - SimpleServiceProtocol

    func invoke(
        request: Distributed_actor_system_InvocationRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Distributed_actor_system_InvocationResponse {
        logger.debug("Received invoke request: \(request.callID)")
        return await actorSystem.handleIncomingInvocation(request)
    }

    func registerActor(
        request: Distributed_actor_system_RegisterActorRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Distributed_actor_system_RegisterActorResponse {
        logger.debug("Received register actor request: \(request.identity.id)")
        return Distributed_actor_system_RegisterActorResponse.with {
            $0.success = true
            $0.message = "Actor registered"
        }
    }

    func ping(
        request: Distributed_actor_system_PingRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Distributed_actor_system_PingResponse {
        logger.debug("Received ping from \(request.nodeHost):\(request.nodePort)")
        return Distributed_actor_system_PingResponse.with {
            $0.alive = actorSystem.isRunning
            $0.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }
}
