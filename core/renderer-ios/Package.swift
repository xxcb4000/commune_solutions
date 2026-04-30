// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommuneRenderer",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "CommuneRenderer",
            targets: ["CommuneRenderer"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk",
            from: "11.0.0"
        )
    ],
    targets: [
        .target(
            name: "CommuneRenderer",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            path: "Sources/CommuneRenderer"
        )
    ]
)
