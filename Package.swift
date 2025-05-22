// Package.swift
// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
      ]
    ),
    .testTarget(name: "USPAuthKitTests", dependencies: ["USPAuthKit"]),
  ]
)
