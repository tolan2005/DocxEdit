#!/usr/bin/swift
//
// generate-icon.swift — генерирует DocxEdit.icns для app-бандла.
// Запускается из скрипта build.sh.
//
import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "DocxEdit.icns"

// Размеры для iconset
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Скруглённый прямоугольник — фон
    let margin = s * 0.06
    let corner = s * 0.22
    let rect   = CGRect(x: margin, y: margin, width: s - margin*2, height: s - margin*2)
    let path   = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Градиент — синий → синий-фиолетовый
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.20, green: 0.48, blue: 0.95, alpha: 1.0),
            CGColor(red: 0.10, green: 0.30, blue: 0.75, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: s * 0.3, y: s * 0.9),
        end:   CGPoint(x: s * 0.7, y: s * 0.1),
        options: []
    )
    ctx.restoreGState()

    // Белая «страница» внутри
    let pageMx = s * 0.22
    let pageW  = s * 0.56
    let pageH  = s * 0.60
    let pageX  = (s - pageW) / 2
    let pageY  = s * 0.17
    let pageCorner = s * 0.06

    let pagePath = CGPath(
        roundedRect: CGRect(x: pageX, y: pageY, width: pageW, height: pageH),
        cornerWidth: pageCorner, cornerHeight: pageCorner, transform: nil
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(pagePath)
    ctx.fillPath()

    // Загнутый уголок страницы
    let foldSize = s * 0.13
    let foldX = pageX + pageW - foldSize
    let foldY = pageY + pageH - foldSize
    ctx.setFillColor(CGColor(red: 0.18, green: 0.40, blue: 0.82, alpha: 0.55))
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: foldX, y: foldY + foldSize))
    foldPath.addLine(to: CGPoint(x: foldX + foldSize, y: foldY))
    foldPath.addLine(to: CGPoint(x: foldX + foldSize, y: foldY + foldSize))
    foldPath.closeSubpath()
    ctx.addPath(foldPath)
    ctx.fillPath()

    // Строчки текста
    let lineColor = CGColor(red: 0.20, green: 0.45, blue: 0.88, alpha: 0.45)
    let lineH = s * 0.045
    let lineSpacing = s * 0.088
    let lineX = pageX + s * 0.09
    let lineMaxW = pageW - s * 0.18
    let startY = pageY + pageH * 0.62
    ctx.setFillColor(lineColor)
    for i in 0..<4 {
        let ly = startY - CGFloat(i) * lineSpacing
        let lw = i == 3 ? lineMaxW * 0.55 : lineMaxW
        let lineRect = CGRect(x: lineX, y: ly, width: lw, height: lineH)
        ctx.fill(lineRect)
    }

    // Буква "D" поверх
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: s * 0.30),
        .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.78, alpha: 1.0),
    ]
    let str = NSAttributedString(string: "D", attributes: attr)
    let strSize = str.size()
    str.draw(at: NSPoint(
        x: pageX + (pageW - strSize.width)  / 2,
        y: pageY + pageH * 0.55
    ))

    img.unlockFocus()
    return img
}

// Создаём временный iconset
let tmpDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("DocxEdit-iconset-\(Int.random(in: 10000...99999))")
let iconsetDir = tmpDir.appendingPathComponent("DocxEdit.iconset")
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (px, filename) in sizes {
    let img = drawIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to generate \(filename)\n", stderr)
        continue
    }
    let dest = iconsetDir.appendingPathComponent(filename)
    try! png.write(to: dest)
}

// Конвертируем в .icns
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", "-o", outputPath, iconsetDir.path]
try! proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("Icon generated: \(outputPath)")
} else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: tmpDir)
