import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Photoshop files deeper than 8 bits and CMYK files are read directly: their channels come down to
/// 8 bits per channel and CMYK's inks are converted to sRGB, with the layers intact.
@MainActor
@Suite(.serialized)
struct PSDDeepAndCMYKTests {
    private func colorImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat,
                            alpha: CGFloat = 1) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let color = try #require(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         components: [red, green, blue, alpha]))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let index = (y * image.width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    /// The same read, with the alpha channel the layer came in with.
    private func pixelRGBA(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int, a: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let index = (y * image.width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }

    /// A layer of `image` filling `bounds`, in a canvas of the given size.
    private func document(_ layers: [PSDRecord], width: Int, height: Int) -> PSDDocument {
        PSDDocument(width: width, height: height, resolution: 72, layers: layers)
    }

    // MARK: Channels

    @Test func sixteenBitSamplesKeepTheirHighByte() throws {
        var raw = Data()
        for value in [0x0000, 0x1234, 0xABCD, 0xFFFF] {
            raw.append(UInt8(value >> 8))
            raw.append(UInt8(value & 0xff))
        }
        let samples = try PSDChannelCoder.decode(compression: 0, width: 4, height: 1, depth: 16, data: raw)
        #expect(samples == [0x00, 0x12, 0xAB, 0xFF])

        // A crop counts its offsets in samples, not bytes.
        let cropped = try PSDChannelCoder.decode(compression: 0, width: 4, height: 1, depth: 16, data: raw,
                                                 crop: PSDCrop(x: 1, y: 0, width: 2, height: 1))
        #expect(cropped == [0x12, 0xAB])
    }

    @Test func sixteenBitRLERowsAreByteRows() throws {
        // Two rows of two 16-bit samples, each row one literal PackBits run of four bytes.
        let rows = [Data([0x00, 0x12, 0x34, 0x56]), Data([0xAB, 0xCD, 0xEF, 0x01])]
        let packed = rows.map { Data([UInt8($0.count - 1)]) + $0 }
        var data = Data()
        for row in packed {
            data.append(UInt8(row.count >> 8))
            data.append(UInt8(row.count & 0xff))
        }
        for row in packed { data.append(row) }

        let samples = try PSDChannelCoder.decode(compression: 1, width: 2, height: 2, depth: 16, data: data)
        #expect(samples == [0x00, 0x34, 0xAB, 0xEF])

        // The same rows, cropped to the second sample of each.
        let cropped = try PSDChannelCoder.decode(compression: 1, width: 2, height: 2, depth: 16, data: data,
                                                 crop: PSDCrop(x: 1, y: 0, width: 1, height: 2))
        #expect(cropped == [0x34, 0xEF])
    }

    @Test func thirtyTwoBitSamplesAreScaled() throws {
        var raw = Data()
        for value in [Float(0), 0.5, 1, 2] {
            withUnsafeBytes(of: value.bitPattern.bigEndian) { raw.append(contentsOf: $0) }
        }
        let samples = try PSDChannelCoder.decode(compression: 0, width: 4, height: 1, depth: 32, data: raw)
        #expect(samples == [0, 128, 255, 255], "out-of-range floats clamp")
    }

    // MARK: Files

    @Test func sixteenBitLayersComeInDirectly() throws {
        let red = try colorImage(width: 2, height: 2, red: 1, green: 0, blue: 0)
        var layer = PSDRecord(id: UUID(), name: "Red")
        layer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        layer.image = red
        let data = try PSDFixture.data(document([layer], width: 2, height: 2), composite: red, depth: 16)

        let parsed = try PSDReader.read(data)
        #expect(parsed.sourceDepth == 16)
        #expect(parsed.layers.map(\.name) == ["Red"])
        let image = try #require(parsed.layers[0].image)
        let sample = try pixel(image, x: 0, y: 0)
        #expect(sample == (255, 0, 0), "16-bit red came back as \(sample)")
    }

    @Test func thirtyTwoBitLayersComeInDirectly() throws {
        let blue = try colorImage(width: 2, height: 2, red: 0, green: 0, blue: 1)
        var layer = PSDRecord(id: UUID(), name: "Blue")
        layer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        layer.image = blue
        let data = try PSDFixture.data(document([layer], width: 2, height: 2), composite: blue, depth: 32)

        let parsed = try PSDReader.read(data)
        #expect(parsed.sourceDepth == 32)
        let image = try #require(parsed.layers[0].image)
        let sample = try pixel(image, x: 0, y: 0)
        #expect(abs(sample.b - 255) <= 1, "32-bit blue came back as \(sample)")
        #expect(sample.r <= 1 && sample.g <= 1, "32-bit blue came back as \(sample)")
    }

    @Test func cmykLayersComeInDirectly() throws {
        let paper = try colorImage(width: 2, height: 2, red: 1, green: 1, blue: 1)
        let solid = try colorImage(width: 2, height: 2, red: 0, green: 0, blue: 0)
        var paperLayer = PSDRecord(id: UUID(), name: "Paper")
        paperLayer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        paperLayer.image = paper
        var inkLayer = PSDRecord(id: UUID(), name: "Ink")
        inkLayer.bounds = CGRect(x: 2, y: 0, width: 2, height: 2)
        inkLayer.image = solid
        let data = try PSDFixture.data(document([paperLayer, inkLayer], width: 4, height: 2),
                                       composite: paper, colorMode: 4)

        let parsed = try PSDReader.read(data)
        #expect(parsed.isCMYK)
        #expect(parsed.layers.map(\.name) == ["Paper", "Ink"])
        let noInk = try pixel(try #require(parsed.layers[0].image), x: 0, y: 0)
        #expect(noInk.r > 240 && noInk.g > 240 && noInk.b > 240, "no ink came back as \(noInk)")
        let fullInk = try pixel(try #require(parsed.layers[1].image), x: 0, y: 0)
        #expect(fullInk.r < 100 && fullInk.g < 100 && fullInk.b < 100, "full ink came back as \(fullInk)")
    }

    @Test func deeperCMYKLayersComeInDirectly() throws {
        let solid = try colorImage(width: 2, height: 2, red: 0, green: 0, blue: 0)
        var layer = PSDRecord(id: UUID(), name: "Ink")
        layer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        layer.image = solid
        let data = try PSDFixture.data(document([layer], width: 2, height: 2), composite: solid,
                                       colorMode: 4, depth: 16)

        let parsed = try PSDReader.read(data)
        #expect(parsed.isCMYK)
        #expect(parsed.sourceDepth == 16)
        let sample = try pixel(try #require(parsed.layers[0].image), x: 0, y: 0)
        #expect(sample.r < 100 && sample.g < 100 && sample.b < 100, "16-bit full ink came back as \(sample)")
    }

    @Test func cmykLayersKeepTheirAlpha() throws {
        let halfInk = try colorImage(width: 2, height: 2, red: 0, green: 0, blue: 0, alpha: 0.5)
        var layer = PSDRecord(id: UUID(), name: "Half")
        layer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        layer.image = halfInk
        let data = try PSDFixture.data(document([layer], width: 2, height: 2), composite: halfInk, colorMode: 4)

        let parsed = try PSDReader.read(data)
        let image = try #require(parsed.layers[0].image)
        let sample = try pixelRGBA(image, x: 0, y: 0)
        #expect(abs(sample.a - 128) <= 2, "alpha came back as \(sample.a)")
        #expect(sample.r < 100 && sample.g < 100 && sample.b < 100, "the ink should still be dark: \(sample)")
    }

    @Test func theReportNamesTheConversions() throws {
        let url = URL(fileURLWithPath: "/tmp/Night Sky.psd")
        var converted = PSDDocument(width: 4, height: 4, resolution: 72, layers: [])
        converted.sourceDepth = 16
        converted.isCMYK = true

        let notes = EditorSession.psdFileNotes(for: url, document: converted)
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.layerName == "Night Sky" })
        #expect(notes.contains { $0.message.contains("16-bit") })
        #expect(notes.contains { $0.message.contains("CMYK") })
        #expect(notes.allSatisfy { $0.message.contains("8 bits") || $0.message.contains("sRGB") })

        // An 8-bit RGB file converts nothing, so the report stays quiet.
        let plain = PSDDocument(width: 4, height: 4, resolution: 72, layers: [])
        #expect(EditorSession.psdFileNotes(for: url, document: plain).isEmpty)
    }
}
