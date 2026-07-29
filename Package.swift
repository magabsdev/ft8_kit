// swift-tools-version: 6.0
import PackageDescription
let package = Package(
 name:"FT8Kit",
 platforms:[.macOS(.v15)],
 products:[.library(name:"FT8DSP", targets:["FT8DSP"])],
 targets:[
  .target(name:"FT8DSP"),
  .testTarget(name:"FT8DSPTests", dependencies:["FT8DSP"])
 ])