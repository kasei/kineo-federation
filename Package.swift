// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kineo-federation",
	products: [
		.library(name: "KineoFederation", targets: ["KineoFederation"]),
	],    
    dependencies: [
		.package(url: "https://github.com/kasei/swift-sparql-syntax.git", from: "0.0.83"),
		.package(url: "https://github.com/kasei/kineo.git", from: "0.0.33"),
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
