//
//  NodeConnection.swift
//  DistributedGRPCActorSystem
//
//  Node-side handler for connecting to routers via bidirectional streaming.
//  Enables nodes behind NAT/firewalls to receive work from routers.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import Logging

// MARK: - Node Connection State

/// Connection state for the node-router stream.
public enum NodeConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(routerId: String)
    case reconnecting(attempt: Int)
    case failed(String) // Store error description instead of Error for Equatable

    public static func failed(_ error: Error) -> NodeConnectionState {
        .failed(String(describing: error))
    }
}

// MARK: - Query Handler Protocol

/// Protocol for handling queries received over the node connection.
public protocol NodeQueryHandler: Sendable {
    /// Handle a query request from the router.
    /// Return an async stream of results to send back.
    func handleQuery(_ request: NodeConnector_QueryRequest) async throws -> AsyncThrowingStream<NodeConnector_QueryResult, Error>

    /// Called when the router requests to cancel a query.
    func cancelQuery(queryId: String) async

    /// Called when the router requests shutdown.
    func handleShutdown(reason: String, gracePeriodSeconds: Int32) async
}

// MARK: - Node Connection Configuration

/// Configuration for the node connection.
public struct NodeConnectionConfiguration: Sendable {
    /// Router endpoint address
    public let routerHost: String
    public let routerPort: Int

    /// Node identification
    public let nodeId: String
    public let nodeName: String
    public let capabilities: [String]
    public let categories: [String]

    /// Device info
    public let deviceOS: String
    public let deviceIdentifier: String

    /// Connection settings
    public let reconnectDelaySeconds: Int
    public let maxReconnectAttempts: Int
    public let healthCheckIntervalSeconds: Int

    /// Transport security
    public let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity

    /// Optional metadata
    public let metadata: [String: String]

    public init(
        routerHost: String,
        routerPort: Int,
        nodeId: String,
        nodeName: String,
        capabilities: [String] = [],
        categories: [String] = [],
        deviceOS: String = "",
        deviceIdentifier: String = "",
        reconnectDelaySeconds: Int = 5,
        maxReconnectAttempts: Int = -1, // -1 = infinite
        healthCheckIntervalSeconds: Int = 30,
        transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity = .tls,
        metadata: [String: String] = [:]
    ) {
        self.routerHost = routerHost
        self.routerPort = routerPort
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.capabilities = capabilities
        self.categories = categories
        self.deviceOS = deviceOS
        self.deviceIdentifier = deviceIdentifier
        self.reconnectDelaySeconds = reconnectDelaySeconds
        self.maxReconnectAttempts = maxReconnectAttempts
        self.healthCheckIntervalSeconds = healthCheckIntervalSeconds
        self.transportSecurity = transportSecurity
        self.metadata = metadata
    }
}

// MARK: - Outbound Message Channel

/// Thread-safe channel for sending messages from query handlers back to the router.
public actor OutboundMessageChannel {
    private var continuation: AsyncStream<NodeConnector_NodeMessage>.Continuation?
    private var stream: AsyncStream<NodeConnector_NodeMessage>?

    public init() {
        let (stream, continuation) = AsyncStream<NodeConnector_NodeMessage>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    /// Send a message to the router.
    public func send(_ message: NodeConnector_NodeMessage) {
        continuation?.yield(message)
    }

    /// Send a query result to the router.
    public func sendResult(_ result: NodeConnector_QueryResult) {
        send(.with { $0.payload = .result(result) })
    }

    /// Send a health update to the router.
    public func sendHealth(_ health: NodeConnector_HealthStatus) {
        send(.with { $0.payload = .health(health) })
    }

    /// Get the stream of outbound messages.
    func getStream() -> AsyncStream<NodeConnector_NodeMessage>? {
        stream
    }

    /// Close the channel.
    func close() {
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - Node Connection

/// Manages the bidirectional streaming connection from a node to a router.
///
/// This actor handles:
/// - Establishing and maintaining the connection
/// - Automatic reconnection on disconnection
/// - Sending registration and health updates
/// - Receiving and dispatching queries to the handler
/// - Sending query results back to the router
///
/// ## Usage
/// ```swift
/// let config = NodeConnectionConfiguration(
///     routerHost: "router.example.com",
///     routerPort: 8443,
///     nodeId: "node-123",
///     nodeName: "My Node",
///     capabilities: ["llm-inference"],
///     transportSecurity: transportSecurity
/// )
///
/// let connection = NodeConnection(
///     configuration: config,
///     queryHandler: myQueryHandler
/// )
///
/// try await connection.connect()
/// ```
public actor NodeConnection {
    private let configuration: NodeConnectionConfiguration
    private let queryHandler: NodeQueryHandler
    private let logger: Logger

    private var state: NodeConnectionState = .disconnected
    private var client: GRPCClient<HTTP2ClientTransport.Posix>?
    private var clientTask: Task<Void, Error>?
    private var connectionTask: Task<Void, Error>?
    private var healthCheckTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var outboundChannel: OutboundMessageChannel?

    /// Current connection state.
    public var connectionState: NodeConnectionState {
        state
    }

    /// Initialize the node connection.
    ///
    /// - Parameters:
    ///   - configuration: Connection configuration
    ///   - queryHandler: Handler for incoming queries
    ///   - logger: Optional logger
    public init(
        configuration: NodeConnectionConfiguration,
        queryHandler: NodeQueryHandler,
        logger: Logger? = nil
    ) {
        self.configuration = configuration
        self.queryHandler = queryHandler
        self.logger = logger ?? Logger(label: "NodeConnection.\(configuration.nodeId)")
    }

    // MARK: - Connection Management

    /// Connect to the router and maintain the connection.
    /// This method will automatically reconnect on disconnection.
    public func connect() async throws {
        guard case .disconnected = state else {
            logger.warning("Already connected or connecting")
            return
        }

        state = .connecting
        try await establishConnection()
    }

    /// Disconnect from the router.
    public func disconnect() async {
        logger.info("Disconnecting from router")

        connectionTask?.cancel()
        connectionTask = nil

        healthCheckTask?.cancel()
        healthCheckTask = nil

        await outboundChannel?.close()
        outboundChannel = nil

        client?.beginGracefulShutdown()
        clientTask?.cancel()
        clientTask = nil
        client = nil

        state = .disconnected
        reconnectAttempt = 0
    }

    // MARK: - Private Methods

    private func establishConnection() async throws {
        logger.info("Connecting to router at \(configuration.routerHost):\(configuration.routerPort)")

        // Create outbound channel for sending messages
        let channel = OutboundMessageChannel()
        self.outboundChannel = channel

        do {
            // Create gRPC client
            let transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: configuration.routerHost, port: configuration.routerPort),
                transportSecurity: configuration.transportSecurity
            )

            let grpcClient = GRPCClient(transport: transport)
            self.client = grpcClient

            // Start client connection in background
            clientTask = Task {
                try await grpcClient.runConnections()
            }

            // Start the bidirectional stream
            let service = NodeConnector_NodeConnectorService.Client(wrapping: grpcClient)
            let config = configuration
            let queryHandler = self.queryHandler
            let loggerCopy = self.logger

            // Run the connection in a task
            connectionTask = Task { [weak self] in
                do {
                    try await service.connect(
                        producer: { writer in
                            // Send registration first
                            try await writer.write(.with {
                                $0.payload = .registration(NodeConnector_NodeRegistration.with {
                                    $0.nodeId = config.nodeId
                                    $0.nodeName = config.nodeName
                                    $0.capabilities = config.capabilities
                                    $0.categories = config.categories
                                    $0.deviceOS = config.deviceOS
                                    $0.deviceIdentifier = config.deviceIdentifier
                                    $0.metadata = config.metadata
                                })
                            })

                            // Forward messages from the outbound channel
                            if let stream = await channel.getStream() {
                                for await message in stream {
                                    try await writer.write(message)
                                }
                            }
                        },
                        handler: { responses in
                            for try await message in responses {
                                await self?.handleRouterMessage(message, channel: channel, queryHandler: queryHandler, logger: loggerCopy)
                            }
                        }
                    )
                } catch {
                    loggerCopy.error("Connection stream ended with error: \(error)")
                    await self?.handleDisconnection(error: error)
                }
            }

        } catch {
            logger.error("Failed to connect: \(error)")
            state = .failed(error)
            await scheduleReconnect()
            throw error
        }
    }

    private func handleRouterMessage(
        _ message: NodeConnector_RouterMessage,
        channel: OutboundMessageChannel,
        queryHandler: NodeQueryHandler,
        logger: Logger
    ) async {
        switch message.payload {
        case .accepted(let accepted):
            logger.info("Connection accepted by router \(accepted.routerId)")
            state = .connected(routerId: accepted.routerId)
            reconnectAttempt = 0

            // Start health check task
            startHealthCheckTask(channel: channel, intervalSeconds: Int(accepted.healthCheckIntervalSeconds))

        case .query(let request):
            logger.debug("Received query: \(request.queryId)")
            // Handle query in a separate task so we don't block the message loop
            Task {
                await self.handleQueryRequest(request, channel: channel, queryHandler: queryHandler, logger: logger)
            }

        case .cancelQuery(let cancel):
            logger.debug("Received cancel for query: \(cancel.queryId)")
            await queryHandler.cancelQuery(queryId: cancel.queryId)

        case .shutdown(let shutdown):
            logger.info("Received shutdown request: \(shutdown.reason)")
            await queryHandler.handleShutdown(
                reason: shutdown.reason,
                gracePeriodSeconds: shutdown.gracePeriodSeconds
            )
            await disconnect()

        case .error(let error):
            logger.error("Received error from router: \(error.code) - \(error.message)")

        case .none:
            break
        }
    }

    private func handleQueryRequest(
        _ request: NodeConnector_QueryRequest,
        channel: OutboundMessageChannel,
        queryHandler: NodeQueryHandler,
        logger: Logger
    ) async {
        do {
            let resultStream = try await queryHandler.handleQuery(request)

            for try await result in resultStream {
                await channel.sendResult(result)
                logger.debug("Sent result for query \(request.queryId): status=\(result.status)")
            }
        } catch {
            logger.error("Query \(request.queryId) failed: \(error)")
            // Send error result
            await channel.sendResult(NodeConnector_QueryResult.with {
                $0.queryId = request.queryId
                $0.status = .failed
                $0.errorMessage = String(describing: error)
            })
        }
    }

    private func startHealthCheckTask(channel: OutboundMessageChannel, intervalSeconds: Int) {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self, configuration] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled else { break }

                await channel.sendHealth(NodeConnector_HealthStatus.with {
                    $0.nodeId = configuration.nodeId
                    $0.isHealthy = true
                    $0.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    // TODO: Populate actual resource usage metrics
                })

                self?.logger.debug("Sent health update")
            }
        }
    }

    private func handleDisconnection(error: Error?) async {
        logger.warning("Disconnected from router")
        state = .disconnected

        healthCheckTask?.cancel()
        healthCheckTask = nil

        await outboundChannel?.close()

        // Schedule reconnection
        await scheduleReconnect()
    }

    private func scheduleReconnect() async {
        reconnectAttempt += 1

        // Check if we've exceeded max attempts
        if configuration.maxReconnectAttempts >= 0 &&
           reconnectAttempt > configuration.maxReconnectAttempts {
            logger.error("Max reconnect attempts exceeded")
            state = .failed(NodeConnectionError.maxReconnectAttemptsExceeded)
            return
        }

        state = .reconnecting(attempt: reconnectAttempt)
        logger.info("Scheduling reconnect attempt \(reconnectAttempt) in \(configuration.reconnectDelaySeconds)s")

        do {
            try await Task.sleep(for: .seconds(configuration.reconnectDelaySeconds))
            try await establishConnection()
        } catch {
            logger.error("Reconnection failed: \(error)")
            await scheduleReconnect()
        }
    }
}

// MARK: - Errors

/// Errors that can occur during node connection.
public enum NodeConnectionError: Error, Sendable {
    case connectionClosed
    case rejected(code: String, message: String)
    case unexpectedResponse
    case maxReconnectAttemptsExceeded
    case notConnected
}

extension NodeConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return "Connection was closed by the router"
        case .rejected(let code, let message):
            return "Connection rejected: \(code) - \(message)"
        case .unexpectedResponse:
            return "Received unexpected response from router"
        case .maxReconnectAttemptsExceeded:
            return "Maximum reconnection attempts exceeded"
        case .notConnected:
            return "Not connected to router"
        }
    }
}
