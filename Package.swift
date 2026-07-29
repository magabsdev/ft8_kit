// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FT8Kit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "FT8Protocol", targets: ["FT8Protocol"]),
        .library(name: "FT8Encoder", targets: ["FT8Encoder"]),
        .library(name: "FT8DSP", targets: ["FT8DSP"]),
        .library(name: "FT8Decoder", targets: ["FT8Decoder"])
    ],
    targets: [
        .target(name: "FT8Protocol"),
        .target(name: "FT8Encoder", dependencies: ["FT8Protocol"]),
        .target(name: "FT8DSP"),
        .target(name: "FT8Decoder", dependencies: ["FT8Protocol", "FT8DSP"]),
        .testTarget(name: "FT8ProtocolTests", dependencies: ["FT8Protocol"]),
        .testTarget(name: "FT8EncoderTests", dependencies: ["FT8Encoder", "FT8Protocol"]),
        .testTarget(name: "FT8DSPTests", dependencies: ["FT8DSP"]),
        .testTarget(
            name: "FT8DecoderTests",
            dependencies: ["FT8Decoder", "FT8Encoder", "FT8DSP", "FT8Protocol"]
        )
    ]
)
