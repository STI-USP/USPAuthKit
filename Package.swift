// Package.swift
// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Captura as compilation conditions vindas do app
let extraFlags: [SwiftSetting] = {
    guard let raw = ProcessInfo.processInfo
            .environment["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] else { return [] }

    let flags = raw.split(whereSeparator: \.isWhitespace).map(String.init)
    return flags.contains("DEV") ? [.define("DEV")] : []
}()

let package = Package(
  name: "USPAuthKit",
  platforms: [
    .iOS(.v12),
  ],
  products: [
    .library(name: "USPAuthKit", targets: ["USPAuthKit"]),
  ],
  targets: [
    .target(
      name: "USPAuthKit",
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("Core"),
        .headerSearchPath("UI"),
        .headerSearchPath("Adapters")
      ],
      swiftSettings: extraFlags
    ),
    .testTarget(name: "USPAuthKitTests", dependencies: ["USPAuthKit"]),
  ]
)
