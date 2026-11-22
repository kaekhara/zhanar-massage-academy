// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZHANARCourseAccess",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ZHANARCourseAccess", targets: ["ZHANARCourseAccess"])],
    targets: [
        .target(
            name: "ZHANARCourseAccess",
            path: "Massage app/Core"
        ),
        .testTarget(
            name: "ZHANARCourseAccessTests",
            dependencies: ["ZHANARCourseAccess"],
            path: "tests-swift"
        )
    ]
)
