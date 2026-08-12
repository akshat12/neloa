import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProductVideoRenderer {
    static let canvas = CGSize(width: 1_280, height: 720)
    static let framesPerSecond: Int32 = 30
    static let duration: TimeInterval = 27
    static let lagoon = NSColor(calibratedRed: 0.00, green: 0.50, blue: 0.52, alpha: 1)
    static let lagoonDeep = NSColor(calibratedRed: 0.02, green: 0.19, blue: 0.25, alpha: 1)
    static let lagoonBright = NSColor(calibratedRed: 0.27, green: 0.78, blue: 0.76, alpha: 1)
    static let coral = NSColor(calibratedRed: 1.00, green: 0.40, blue: 0.38, alpha: 1)

    let outputDirectory: URL
    let icon: NSImage?

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
        icon = NSImage(contentsOfFile: "Resources/AppIcon-1024.png")
    }

    func render() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let videoURL = outputDirectory.appendingPathComponent("neloa-introduction.mp4")
        let previewURL = outputDirectory.appendingPathComponent("neloa-preview.gif")
        let posterURL = outputDirectory.appendingPathComponent("neloa-poster.png")
        try? FileManager.default.removeItem(at: videoURL)
        try? FileManager.default.removeItem(at: previewURL)
        try? FileManager.default.removeItem(at: posterURL)

        try await renderVideo(to: videoURL)
        try renderGIF(to: previewURL)
        let poster = frame(at: 1.7, size: Self.canvas)
        try pngData(for: poster).write(to: posterURL, options: .atomic)
    }

    private func renderVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(Self.canvas.width),
            AVVideoHeightKey: Int(Self.canvas.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_800_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(Self.canvas.width),
                kCVPixelBufferHeightKey as String: Int(Self.canvas.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else { throw RenderError.cannotAddWriterInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RenderError.cannotStartWriter }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(Self.duration * Double(Self.framesPerSecond))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let time = Double(index) / Double(Self.framesPerSecond)
            let image = frame(at: time, size: Self.canvas)
            guard let buffer = pixelBuffer(from: image, pool: adaptor.pixelBufferPool) else {
                throw RenderError.cannotCreatePixelBuffer
            }
            let presentationTime = CMTime(value: CMTimeValue(index), timescale: Self.framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? RenderError.cannotAppendFrame
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RenderError.cannotFinishWriter }
    }

    private func renderGIF(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            0,
            nil
        ) else { throw RenderError.cannotCreateGIF }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let previewSize = CGSize(width: 960, height: 540)
        let previewDuration: TimeInterval = 13.5
        let previewFPS = 10
        let count = Int(previewDuration * Double(previewFPS))
        for index in 0..<count {
            let timeline = Double(index) / Double(previewFPS) * 2
            let image = frame(at: min(Self.duration - 0.01, timeline), size: previewSize)
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(previewFPS)]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw RenderError.cannotFinishGIF }
    }

    private func frame(at time: TimeInterval, size: CGSize) -> CGImage {
        let scale = size.width / Self.canvas.width
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        drawBackground(in: context, time: time)

        let scene = min(5, Int(time / 4.5))
        let local = time - Double(scene) * 4.5
        let entrance = smoothstep(0, 0.65, local)
        let exit = 1 - smoothstep(3.9, 4.5, local)
        context.saveGState()
        context.setAlpha(entrance * exit)
        context.translateBy(x: 0, y: (1 - entrance) * -22 + (1 - exit) * 18)
        switch scene {
        case 0: drawOpening(in: context, time: local)
        case 1: drawTeach(in: context, time: local)
        case 2: drawUnderstanding(in: context, time: local)
        case 3: drawChange(in: context, time: local)
        case 4: drawPreview(in: context, time: local)
        default: drawFinal(in: context, time: local)
        }
        context.restoreGState()

        return context.makeImage()!
    }

    private func drawBackground(in context: CGContext, time: TimeInterval) {
        let colors = [
            Self.lagoonDeep.cgColor,
            NSColor(calibratedRed: 0.025, green: 0.28, blue: 0.31, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.015, green: 0.11, blue: 0.17, alpha: 1).cgColor
        ] as CFArray
        let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.54, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 720), end: CGPoint(x: 1_280, y: 0), options: [])

        context.saveGState()
        context.setBlendMode(.screen)
        context.setAlpha(0.12)
        let drift = sin(time * 0.35) * 50
        context.setFillColor(Self.lagoonBright.cgColor)
        context.fillEllipse(in: CGRect(x: 900 + drift, y: 470, width: 430, height: 430))
        context.setFillColor(Self.coral.cgColor)
        context.fillEllipse(in: CGRect(x: -170 - drift * 0.4, y: -100, width: 420, height: 420))
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.035).cgColor)
        context.setLineWidth(1)
        for x in stride(from: 0, through: 1_280, by: 64) {
            context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: 720))
        }
        for y in stride(from: 0, through: 720, by: 64) {
            context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: 1_280, y: y))
        }
        context.strokePath()
    }

    private func drawOpening(in context: CGContext, time: TimeInterval) {
        let iconScale = 0.88 + smoothstep(0, 1.0, time) * 0.12
        if let icon, let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.translateBy(x: 142, y: 438)
            context.scaleBy(x: iconScale, y: iconScale)
            context.draw(cgIcon, in: CGRect(x: -60, y: -60, width: 120, height: 120))
            context.restoreGState()
        }
        drawText("Neloa", at: CGPoint(x: 226, y: 414), font: 64, weight: .heavy, color: .white, in: context)
        drawText("Show it once.", at: CGPoint(x: 82, y: 274), font: 66, weight: .bold, color: .white, in: context)
        drawText("Then just say what changed.", at: CGPoint(x: 82, y: 194), font: 52, weight: .semibold, color: Self.lagoonBright, in: context)
        drawPill("Private on your Mac", x: 83, y: 118, color: Self.lagoon, icon: "●", in: context)
        drawPill("Built for everyday work", x: 332, y: 118, color: Self.coral, icon: "✦", in: context)
    }

    private func drawTeach(in context: CGContext, time: TimeInterval) {
        drawEyebrow("1  TEACH", at: CGPoint(x: 74, y: 642), in: context)
        drawText("Do the task naturally.", at: CGPoint(x: 74, y: 566), font: 48, weight: .bold, color: .white, in: context)
        drawText("Neloa watches the screen and listens to your explanation.", at: CGPoint(x: 74, y: 518), font: 24, weight: .medium, color: mutedWhite, in: context)
        drawWindow(in: context, rect: CGRect(x: 74, y: 86, width: 760, height: 380), title: "Testing Spreadsheet") {
            drawSpreadsheet(in: context, rect: CGRect(x: 96, y: 110, width: 716, height: 308), time: time)
        }
        drawVoiceCard(in: context, x: 866, y: 190, time: time)
    }

    private func drawUnderstanding(in context: CGContext, time: TimeInterval) {
        drawEyebrow("2  UNDERSTAND", at: CGPoint(x: 74, y: 642), in: context)
        drawText("Clicks become a workflow.", at: CGPoint(x: 74, y: 566), font: 48, weight: .bold, color: .white, in: context)
        drawText("Neloa combines actions, vision, and your words—locally.", at: CGPoint(x: 74, y: 518), font: 24, weight: .medium, color: mutedWhite, in: context)

        let cards = [
            ("Open Google Drive", "Web", "safari.fill"),
            ("Open Testing Spreadsheet", "Click", "cursorarrow.click"),
            ("Create Sheet2", "Click", "plus.square"),
            ("Set Sheet2!A1 to X", "Input", "text.cursor"),
            ("Set Sheet2!B1 to 3", "Input", "text.cursor")
        ]
        let reveal = Int(floor(max(0, time - 0.25) / 0.48)) + 1
        for (index, item) in cards.enumerated() where index < reveal {
            let y = 416 - CGFloat(index) * 72
            drawStepCard(index: index + 1, title: item.0, tag: item.1, y: y, active: index == min(cards.count - 1, reveal - 1), in: context)
        }
        drawLocalBadge(in: context, x: 874, y: 155)
    }

    private func drawChange(in context: CGContext, time: TimeInterval) {
        drawEyebrow("3  CHANGE IT", at: CGPoint(x: 74, y: 642), in: context)
        drawText("Every run can be different.", at: CGPoint(x: 74, y: 566), font: 48, weight: .bold, color: .white, in: context)
        drawText("Ask by voice. Neloa changes only the safe, flexible values.", at: CGPoint(x: 74, y: 518), font: 24, weight: .medium, color: mutedWhite, in: context)

        roundedRect(CGRect(x: 74, y: 260, width: 1_132, height: 178), radius: 34, fill: NSColor.white.withAlphaComponent(0.095), stroke: NSColor.white.withAlphaComponent(0.15), in: context)
        context.setFillColor(Self.coral.cgColor)
        context.fillEllipse(in: CGRect(x: 106, y: 319, width: 60, height: 60))
        drawText("●", at: CGPoint(x: 125, y: 336), font: 24, weight: .bold, color: .white, in: context)
        let sentence = "Use Z in A1 and 7 in B1."
        let shown = Int(Double(sentence.count) * smoothstep(0.45, 2.8, time))
        drawText(String(sentence.prefix(shown)), at: CGPoint(x: 194, y: 342), font: 34, weight: .semibold, color: .white, in: context)
        drawWaveform(in: context, rect: CGRect(x: 195, y: 294, width: 620, height: 28), time: time)
        drawPill("A1  X → Z", x: 212, y: 156, color: Self.lagoon, icon: "✓", in: context)
        drawPill("B1  3 → 7", x: 462, y: 156, color: Self.lagoon, icon: "✓", in: context)
    }

    private func drawPreview(in context: CGContext, time: TimeInterval) {
        drawEyebrow("4  REVIEW", at: CGPoint(x: 74, y: 642), in: context)
        drawText("See exactly what will happen.", at: CGPoint(x: 74, y: 566), font: 48, weight: .bold, color: .white, in: context)
        drawText("Nothing runs until you approve the preview.", at: CGPoint(x: 74, y: 518), font: 24, weight: .medium, color: mutedWhite, in: context)

        roundedRect(CGRect(x: 74, y: 100, width: 1_132, height: 358), radius: 28, fill: NSColor(calibratedWhite: 0.98, alpha: 1), stroke: NSColor.white.withAlphaComponent(0.35), in: context)
        drawText("This run", at: CGPoint(x: 112, y: 402), font: 28, weight: .bold, color: Self.lagoonDeep, in: context)
        drawText("For this run, Neloa will use Z and 7.", at: CGPoint(x: 112, y: 365), font: 20, weight: .medium, color: NSColor.darkGray, in: context)
        drawChangeRow(from: "X", to: "Z", target: "Sheet2!A1", y: 272, in: context)
        drawChangeRow(from: "3", to: "7", target: "Sheet2!B1", y: 188, in: context)
        let pulse = 0.88 + sin(time * 4) * 0.04
        context.saveGState()
        context.translateBy(x: 1_035, y: 163)
        context.scaleBy(x: pulse, y: pulse)
        roundedRect(CGRect(x: -126, y: -31, width: 252, height: 62), radius: 31, fill: Self.lagoon, stroke: nil, in: context)
        drawText("Run this time", at: CGPoint(x: -72, y: -7), font: 20, weight: .bold, color: .white, in: context)
        context.restoreGState()
    }

    private func drawFinal(in context: CGContext, time: TimeInterval) {
        if let icon, let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgIcon, in: CGRect(x: 556, y: 490, width: 168, height: 168))
        }
        drawCentered("Automation for everyone.", y: 400, font: 54, weight: .bold, color: .white, in: context)
        drawCentered("Teach once. Adapt by voice. Stay in control.", y: 332, font: 28, weight: .medium, color: Self.lagoonBright, in: context)
        roundedRect(CGRect(x: 457, y: 206, width: 366, height: 72), radius: 36, fill: Self.lagoon, stroke: NSColor.white.withAlphaComponent(0.22), in: context)
        drawCentered("Try Neloa on macOS", y: 232, font: 22, weight: .bold, color: .white, in: context)
        drawCentered("Private · Local AI · Open source", y: 128, font: 19, weight: .medium, color: mutedWhite, in: context)
    }

    private func drawSpreadsheet(in context: CGContext, rect: CGRect, time: TimeInterval) {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        drawText("A", at: CGPoint(x: rect.minX + 140, y: rect.maxY - 42), font: 16, weight: .semibold, color: .darkGray, in: context)
        drawText("B", at: CGPoint(x: rect.minX + 335, y: rect.maxY - 42), font: 16, weight: .semibold, color: .darkGray, in: context)
        context.setStrokeColor(NSColor(calibratedWhite: 0.84, alpha: 1).cgColor)
        context.setLineWidth(1)
        for x in stride(from: rect.minX + 48, through: rect.maxX - 18, by: 195) {
            context.move(to: CGPoint(x: x, y: rect.minY + 28)); context.addLine(to: CGPoint(x: x, y: rect.maxY - 54))
        }
        for y in stride(from: rect.minY + 28, through: rect.maxY - 54, by: 54) {
            context.move(to: CGPoint(x: rect.minX + 48, y: y)); context.addLine(to: CGPoint(x: rect.maxX - 18, y: y))
        }
        context.strokePath()

        if time > 1.0 { drawText("X", at: CGPoint(x: rect.minX + 72, y: rect.maxY - 98), font: 26, weight: .semibold, color: Self.lagoonDeep, in: context) }
        if time > 2.2 { drawText("3", at: CGPoint(x: rect.minX + 268, y: rect.maxY - 98), font: 26, weight: .semibold, color: Self.lagoonDeep, in: context) }
        let column: CGFloat = time < 2.2 ? rect.minX + 48 : rect.minX + 243
        context.setStrokeColor(Self.lagoon.cgColor)
        context.setLineWidth(4)
        context.stroke(CGRect(x: column, y: rect.maxY - 126, width: 195, height: 54))
        roundedRect(CGRect(x: rect.minX + 60, y: rect.minY + 3, width: 112, height: 32), radius: 8, fill: NSColor(calibratedWhite: 0.92, alpha: 1), stroke: nil, in: context)
        drawText("Sheet2", at: CGPoint(x: rect.minX + 86, y: rect.minY + 13), font: 14, weight: .semibold, color: Self.lagoonDeep, in: context)
    }

    private func drawVoiceCard(in context: CGContext, x: CGFloat, y: CGFloat, time: TimeInterval) {
        roundedRect(CGRect(x: x, y: y, width: 340, height: 226), radius: 28, fill: NSColor.white.withAlphaComponent(0.10), stroke: NSColor.white.withAlphaComponent(0.16), in: context)
        drawText("Explain the choices", at: CGPoint(x: x + 28, y: y + 174), font: 22, weight: .bold, color: .white, in: context)
        drawWaveform(in: context, rect: CGRect(x: x + 28, y: y + 112, width: 284, height: 42), time: time)
        drawText("“Put X in A1 and 3 in B1.”", at: CGPoint(x: x + 28, y: y + 65), font: 17, weight: .medium, color: mutedWhite, in: context)
        drawPill("Recording", x: x + 28, y: y + 20, color: Self.coral, icon: "●", in: context)
    }

    private func drawStepCard(index: Int, title: String, tag: String, y: CGFloat, active: Bool, in context: CGContext) {
        roundedRect(CGRect(x: 74, y: y, width: 786, height: 58), radius: 17, fill: active ? NSColor.white.withAlphaComponent(0.17) : NSColor.white.withAlphaComponent(0.085), stroke: active ? Self.lagoonBright.withAlphaComponent(0.65) : NSColor.white.withAlphaComponent(0.10), in: context)
        context.setFillColor((active ? Self.lagoonBright : Self.lagoon).cgColor)
        context.fillEllipse(in: CGRect(x: 92, y: y + 13, width: 32, height: 32))
        drawText("\(index)", at: CGPoint(x: 103, y: y + 23), font: 14, weight: .bold, color: Self.lagoonDeep, in: context)
        drawText(title, at: CGPoint(x: 144, y: y + 21), font: 20, weight: .semibold, color: .white, in: context)
        drawText(tag.uppercased(), at: CGPoint(x: 746, y: y + 22), font: 12, weight: .bold, color: Self.lagoonBright, in: context)
    }

    private func drawLocalBadge(in context: CGContext, x: CGFloat, y: CGFloat) {
        roundedRect(CGRect(x: x, y: y, width: 332, height: 258), radius: 30, fill: NSColor.white.withAlphaComponent(0.09), stroke: NSColor.white.withAlphaComponent(0.15), in: context)
        drawText("Private intelligence", at: CGPoint(x: x + 30, y: y + 194), font: 24, weight: .bold, color: .white, in: context)
        drawText("Vision", at: CGPoint(x: x + 30, y: y + 144), font: 17, weight: .semibold, color: Self.lagoonBright, in: context)
        drawText("+ Actions", at: CGPoint(x: x + 30, y: y + 106), font: 17, weight: .semibold, color: Self.lagoonBright, in: context)
        drawText("+ Your voice", at: CGPoint(x: x + 30, y: y + 68), font: 17, weight: .semibold, color: Self.lagoonBright, in: context)
        drawPill("ON THIS MAC", x: x + 30, y: y + 20, color: Self.lagoon, icon: "✓", in: context)
    }

    private func drawChangeRow(from: String, to: String, target: String, y: CGFloat, in context: CGContext) {
        roundedRect(CGRect(x: 112, y: y, width: 710, height: 66), radius: 16, fill: NSColor(calibratedWhite: 0.94, alpha: 1), stroke: NSColor(calibratedWhite: 0.86, alpha: 1), in: context)
        drawText(target, at: CGPoint(x: 138, y: y + 23), font: 18, weight: .semibold, color: Self.lagoonDeep, in: context)
        drawText(from, at: CGPoint(x: 514, y: y + 23), font: 19, weight: .medium, color: .gray, in: context)
        drawText("→", at: CGPoint(x: 570, y: y + 23), font: 20, weight: .bold, color: Self.lagoon, in: context)
        drawText(to, at: CGPoint(x: 630, y: y + 23), font: 20, weight: .bold, color: Self.lagoon, in: context)
    }

    private func drawWindow(in context: CGContext, rect: CGRect, title: String, content: () -> Void) {
        roundedRect(rect, radius: 24, fill: NSColor(calibratedWhite: 0.96, alpha: 1), stroke: NSColor.white.withAlphaComponent(0.28), in: context)
        context.setFillColor(NSColor(calibratedWhite: 0.90, alpha: 1).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.maxY - 54, width: rect.width, height: 54))
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: rect.minX + 20 + CGFloat(index) * 23, y: rect.maxY - 34, width: 12, height: 12))
        }
        drawText(title, at: CGPoint(x: rect.minX + 106, y: rect.maxY - 35), font: 16, weight: .semibold, color: Self.lagoonDeep, in: context)
        content()
    }

    private func drawWaveform(in context: CGContext, rect: CGRect, time: TimeInterval) {
        context.setStrokeColor(Self.lagoonBright.cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        let bars = 42
        for index in 0..<bars {
            let fraction = CGFloat(index) / CGFloat(bars - 1)
            let phase = Double(index) * 0.77 + time * 7.2
            let amplitude = rect.height * CGFloat(0.15 + 0.72 * abs(sin(phase)) * (0.4 + 0.6 * sin(Double(index) * 0.21).magnitude))
            let x = rect.minX + fraction * rect.width
            context.move(to: CGPoint(x: x, y: rect.midY - amplitude / 2))
            context.addLine(to: CGPoint(x: x, y: rect.midY + amplitude / 2))
        }
        context.strokePath()
    }

    private func drawPill(_ text: String, x: CGFloat, y: CGFloat, color: NSColor, icon: String, in context: CGContext) {
        let width = CGFloat(text.count * 10 + 68)
        roundedRect(CGRect(x: x, y: y, width: width, height: 44), radius: 22, fill: color.withAlphaComponent(0.30), stroke: color.withAlphaComponent(0.78), in: context)
        drawText(icon, at: CGPoint(x: x + 17, y: y + 15), font: 13, weight: .bold, color: color, in: context)
        drawText(text, at: CGPoint(x: x + 39, y: y + 14), font: 15, weight: .bold, color: .white, in: context)
    }

    private func drawEyebrow(_ text: String, at point: CGPoint, in context: CGContext) {
        drawText(text, at: point, font: 16, weight: .bold, color: Self.lagoonBright, in: context)
    }

    private func drawCentered(_ text: String, y: CGFloat, font: CGFloat, weight: NSFont.Weight, color: NSColor, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: font, weight: weight),
            .foregroundColor: color
        ]
        let width = (text as NSString).size(withAttributes: attributes).width
        drawText(text, at: CGPoint(x: (1_280 - width) / 2, y: y), font: font, weight: weight, color: color, in: context)
    }

    private func drawText(_ text: String, at point: CGPoint, font: CGFloat, weight: NSFont.Weight, color: NSColor, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: font, weight: weight),
            .foregroundColor: color,
            .kern: font >= 42 ? -1.2 : 0
        ])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor?, stroke: NSColor?, in context: CGContext) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let fill { context.setFillColor(fill.cgColor); context.addPath(path); context.fillPath() }
        if let stroke { context.setStrokeColor(stroke.cgColor); context.setLineWidth(1); context.addPath(path); context.strokePath() }
    }

    private var mutedWhite: NSColor { NSColor.white.withAlphaComponent(0.72) }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> CGFloat {
        let value = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return CGFloat(value * value * (3 - 2 * value))
    }

    private func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32ARGB, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let context = CGContext(
            data: baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private func pngData(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.cannotCreatePNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.cannotCreatePNG }
        return data as Data
    }

    enum RenderError: Error {
        case cannotAddWriterInput
        case cannotStartWriter
        case cannotCreatePixelBuffer
        case cannotAppendFrame
        case cannotFinishWriter
        case cannotCreateGIF
        case cannotFinishGIF
        case cannotCreatePNG
    }
}

let renderer = ProductVideoRenderer(outputDirectory: URL(fileURLWithPath: "docs/media", isDirectory: true))
try await renderer.render()
print("Rendered docs/media/neloa-introduction.mp4, neloa-preview.gif, and neloa-poster.png")
