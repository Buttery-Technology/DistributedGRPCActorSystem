//
//  Serialization.swift
//  DistributedGRPCActorSystem
//
//  Created by Jonathan Holland on 12/10/25.
//

import Distributed
import Foundation

// MARK: - Errors

/// Errors that can occur during distributed actor operations
public enum DistributedActorSystemError: Error, Sendable {
    case actorNotFound(ActorIdentity)
    case serializationFailed(String)
    case deserializationFailed(String)
    case connectionFailed(NetworkAddress, underlying: Error?)
    case invocationFailed(String)
    case timeout
    case nodeUnavailable(NetworkAddress)
    case unknownMethod(String)
}

// MARK: - Invocation Envelope

/// Wire format for method invocations
public struct InvocationEnvelope: Codable, Sendable {
    public let methodName: String
    public let arguments: [Data]
    public let genericSubstitutions: [String]

    public init(methodName: String, arguments: [Data], genericSubstitutions: [String]) {
        self.methodName = methodName
        self.arguments = arguments
        self.genericSubstitutions = genericSubstitutions
    }
}

// MARK: - Invocation Encoder

/// Encoder for distributed method invocations
public final class GRPCInvocationEncoder: DistributedTargetInvocationEncoder, @unchecked Sendable {
    public typealias SerializationRequirement = Codable

    private let encoder: JSONEncoder
    private(set) var methodName: String = ""
    private(set) var arguments: [Data] = []
    public private(set) var genericSubstitutions: [String] = []

    public init() {
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func recordGenericSubstitution<T>(_ type: T.Type) throws {
        genericSubstitutions.append(String(describing: type))
    }

    public func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {
        let data = try encoder.encode(argument.value)
        arguments.append(data)
    }

    public func recordReturnType<R: Codable>(_ type: R.Type) throws {
        // Return type is handled by the result handler
    }

    public func recordErrorType<E: Error>(_ type: E.Type) throws {
        // Error type is handled by the result handler
    }

    public func doneRecording() throws {
        // Finalize encoding - nothing to do here
    }

    /// Serialize the complete invocation to wire format
    public func encode() -> Data {
        let envelope = InvocationEnvelope(
            methodName: methodName,
            arguments: arguments,
            genericSubstitutions: genericSubstitutions
        )
        return (try? encoder.encode(envelope)) ?? Data()
    }
}

// MARK: - Invocation Decoder

/// Decoder for distributed method invocations
public final class GRPCInvocationDecoder: DistributedTargetInvocationDecoder, @unchecked Sendable {
    public typealias SerializationRequirement = Codable

    private let decoder: JSONDecoder
    private let envelope: InvocationEnvelope
    private var argumentIndex: Int = 0

    public init(data: Data) {
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode the envelope, use empty if fails
        if let envelope = try? decoder.decode(InvocationEnvelope.self, from: data) {
            self.envelope = envelope
        } else {
            self.envelope = InvocationEnvelope(methodName: "", arguments: [], genericSubstitutions: [])
        }
    }

    public func decodeGenericSubstitutions() throws -> [Any.Type] {
        // Type registry would be needed for full implementation
        return []
    }

    public func decodeNextArgument<Value: Codable>() throws -> Value {
        guard argumentIndex < envelope.arguments.count else {
            throw DistributedActorSystemError.deserializationFailed(
                "Argument index out of bounds: \(argumentIndex), total: \(envelope.arguments.count)"
            )
        }

        let data = envelope.arguments[argumentIndex]
        argumentIndex += 1

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw DistributedActorSystemError.deserializationFailed(
                "Failed to decode argument \(argumentIndex - 1): \(error)"
            )
        }
    }

    public func decodeErrorType() throws -> Any.Type? {
        return nil
    }

    public func decodeReturnType() throws -> Any.Type? {
        return nil
    }
}

// MARK: - Result Handler

/// Result handler for distributed calls
public final class GRPCResultHandler: DistributedTargetInvocationResultHandler, @unchecked Sendable {
    public typealias SerializationRequirement = Codable

    private let encoder: JSONEncoder
    public private(set) var resultData: Data?
    public private(set) var errorData: Data?
    public private(set) var error: Error?

    public init() {
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func onReturn<Success: Codable>(value: Success) async throws {
        resultData = try encoder.encode(value)
    }

    public func onReturnVoid() async throws {
        // Empty data represents void return
        resultData = Data()
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        self.error = error
        let envelope = ErrorEnvelope(
            type: String(describing: type(of: error)),
            message: String(describing: error)
        )
        errorData = try encoder.encode(envelope)
    }
}

// MARK: - Error Envelope

/// Wire format for errors
public struct ErrorEnvelope: Codable, Sendable {
    public let type: String
    public let message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}
