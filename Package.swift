// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DistributedGRPCActorSystem",
	platforms: [
		.macOS(.v15),
	],
    products: [
        .library(
            name: "DistributedGRPCActorSystem",
            targets: ["DistributedGRPCActorSystem"]
        ),
    ],
	dependencies: [
		.package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
		.package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
		.package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
	],
    targets: [
        .target(
            name: "DistributedGRPCActorSystem",
			dependencies: [
				.product(name: "GRPCCore", package: "grpc-swift-2"),
				.product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
				.product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
				.product(name: "Logging", package: "swift-log"),
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
			]
        ),
        .testTarget(
            name: "DistributedGRPCActorSystemTests",
            dependencies: ["DistributedGRPCActorSystem"]
        ),
    ]
)
