// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YouHaveAMeeting",
    platforms: [.macOS("26.0")],
    targets: [
        // No dependencies. Tests use the Testing library from the Xcode
        // toolchain, so nothing is fetched or resolved.
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
            dependencies: ["YouHaveAMeetingCore"],
            path: "Tests/YouHaveAMeetingTests"
        ),
    ]
)
