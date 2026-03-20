// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RoamOpenAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoamOpenAPI", targets: ["RoamOpenAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "RoamOpenAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
    ]
)
