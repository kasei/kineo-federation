// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kineo-federation",
    dependencies: [
		.package(url: "https://github.com/kasei/swift-sparql-syntax.git", from: "0.0.41"),
		.package(url: "https://github.com/kasei/swift-serd.git", from: "0.0.0"),
		.package(url: "https://github.com/kasei/kineo.git", from: "0.0.16"),
    ],
    targets: [
        .target(
            name: "kineo-federation",
            dependencies: ["Kineo", "SPARQLSyntax"]),
    ]
)
