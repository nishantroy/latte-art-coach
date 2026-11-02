// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LatteCore",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [.library(name: "LatteCore", targets: ["LatteCore"])],
  targets: [
    .target(name: "LatteCore"),
    .testTarget(
      name: "LatteCoreTests",
      dependencies: ["LatteCore"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
