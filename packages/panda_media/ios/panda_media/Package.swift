// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "panda_media",
  platforms: [.iOS("15.0")],
  products: [.library(name: "panda-media", targets: ["panda_media"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [.target(name: "panda_media", dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
    resources: [.process("PrivacyInfo.xcprivacy")])]
)
