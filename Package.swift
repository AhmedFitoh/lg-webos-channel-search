// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LGChannelSearch",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LGChannelSearch",
            targets: ["LGChannelSearch"]
        )
    ],
    targets: [
        .target(
            name: "LGChannelSearch",
            path: ".",
            exclude: [
                "App",
                "Features",
                "Tests/Fixtures",
                "Tests/ArabicNormalizerTests.swift",
                "Tests/SearchEngineTests.swift",
                "Tests/SSAPMessageTests.swift",
                "Tests/ChannelRepositoryTests.swift",
                "project.yml",
                "LGChannelSearch.xcodeproj",
                "LICENSE",
                "README.md",
                "docs"
            ],
            sources: [
                "Core",
                "Data",
                "Search",
                "Tests/Mocks"
            ]
        ),
        .testTarget(
            name: "LGChannelSearchTests",
            dependencies: ["LGChannelSearch"],
            path: "Tests",
            exclude: [
                "Mocks",
                "Fixtures"
            ]
        )
    ]
)
