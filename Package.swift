// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YouHaveAMeeting",
    platforms: [.macOS("26.0")],
    dependencies: [
        // The app itself has no dependencies. This one is test-only: the
        // Command Line Tools toolchain ships neither Testing nor XCTest
        // (both come with full Xcode), so swift-testing is vendored.
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
    ],
    targets: [
        .target(
            name: "YouHaveAMeetingCore",
            path: "Sources/YouHaveAMeetingCore"
        ),
        .executableTarget(
            name: "YouHaveAMeeting",
            dependencies: ["YouHaveAMeetingCore"],
            path: "Sources/YouHaveAMeeting"
        ),
        .testTarget(
            name: "YouHaveAMeetingTests",
            dependencies: [
                "YouHaveAMeetingCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/YouHaveAMeetingTests"
        ),
    ]
)
