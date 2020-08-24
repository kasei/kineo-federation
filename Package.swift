// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KineoFederation",
    platforms: [.macOS(.v10_15)],
	products: [
		.library(name: "KineoFederation", targets: ["KineoFederation"]),
	],    
    dependencies: [
		.package(name: "SPARQLSyntax", url: "https://github.com/kasei/swift-sparql-syntax.git", from: "0.0.114"),
		.package(name: "Kineo", url: "https://github.com/kasei/kineo.git", from: "0.0.33"),
    ],
    targets: [
    	.target(
    		name: "KineoFederation",
			dependencies: ["Kineo", "SPARQLSyntax"]
    	),
        .target(
            name: "kineo-federation",
            dependencies: ["KineoFederation"]),
    ]
)
