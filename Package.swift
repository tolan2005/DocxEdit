// swift-tools-version: 5.9
// Package.swift — DocxEdit R01 (Genesis / MVP)
//
// Корневой Swift Package, описывающий модули DocxEdit.
// ВАЖНО: этот пакет используется для разработки и тестирования ядра
// (DocxCore, DocxIO, RtfIO, MarkdownIO, PdfExporter, EncodingDetector).
//
// Само macOS-приложение (DocxEdit.app) собирается через Xcode-проект
// `App/DocxEdit.xcodeproj`, который линкуется к этим библиотекам.
// Это разделение нужно, чтобы ядро можно было собирать и тестировать
// кросс-платформенно через `swift test`, а UI — только на macOS.

import PackageDescription

let package = Package(
    name: "DocxEdit",
    defaultLocalization: "ru",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Библиотеки, на которые линкуется приложение
        .library(name: "DocxCore", targets: ["DocxCore"]),
        .library(name: "DocxIO", targets: ["DocxIO"]),
        .library(name: "RtfIO", targets: ["RtfIO"]),
        .library(name: "MarkdownIO", targets: ["MarkdownIO"]),
        .library(name: "PdfExporter", targets: ["PdfExporter"]),
        .library(name: "EncodingDetector", targets: ["EncodingDetector"]),
    ],
    dependencies: [
        // ZIP-архивы для DOCX (Office Open XML — это ZIP)
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // Markdown (CommonMark + GFM-расширения)
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        // Snapshot-тесты рендера NSAttributedString (v0.5.2)
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0"),
    ],
    targets: [
        // MARK: - Базовые модули
        .target(
            name: "DocxCore",
            path: "Sources/DocxCore/Sources",
            resources: []
        ),
        .target(
            name: "EncodingDetector",
            dependencies: ["DocxCore"],
            path: "Sources/EncodingDetector/Sources"
        ),
        .target(
            name: "DocxIO",
            dependencies: [
                "DocxCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/DocxIO/Sources"
        ),
        .target(
            name: "RtfIO",
            dependencies: ["DocxCore"],
            path: "Sources/RtfIO/Sources"
        ),
        .target(
            name: "MarkdownIO",
            dependencies: [
                "DocxCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/MarkdownIO/Sources"
        ),
        .target(
            name: "PdfExporter",
            dependencies: ["DocxCore"],
            path: "Sources/PdfExporter/Sources"
        ),

        // MARK: - Приложение (executable)
        .executableTarget(
            name: "DocxEdit",
            dependencies: [
                "DocxCore",
                "DocxIO",
                "RtfIO",
                "MarkdownIO",
                "PdfExporter",
                "EncodingDetector",
            ],
            path: "Sources/DocxEdit/Sources",
            resources: [
                // v0.6.2 (R09): базовая EN-локализация. Полный sweep всех
                // Ru-строк — задача R10.
                .process("Resources"),
            ]
        ),

        // MARK: - Тесты
        .testTarget(
            name: "DocxCoreTests",
            dependencies: ["DocxCore", "EncodingDetector"],
            path: "Tests/DocxCoreTests"
        ),
        .testTarget(
            name: "DocxIOTests",
            dependencies: ["DocxIO", "DocxCore", "MarkdownIO"],
            path: "Tests/DocxIOTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "RtfIOTests",
            dependencies: ["RtfIO", "DocxCore"],
            path: "Tests/RtfIOTests"
        ),
        .testTarget(
            name: "MarkdownIOTests",
            dependencies: ["MarkdownIO", "DocxCore"],
            path: "Tests/MarkdownIOTests"
        ),
        .testTarget(
            name: "DocxEditTests",
            dependencies: [
                "DocxEdit", "DocxCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/DocxEditTests",
            exclude: ["__Snapshots__"]
        ),
    ]
)
