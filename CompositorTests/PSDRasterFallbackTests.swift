import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Flattened Photoshop files, and the modes the reader doesn't take at all: those come in as
/// Photoshop's own merged image, which `ImageImporter.decode(flattenedPhotoshop:)` reads.
@Suite("Photoshop raster fallback")
struct PSDRasterFallbackTests {
    /// A flattened Photoshop file: header, empty sections, then raw channel planes.
    private func flattened(width: Int, height: Int, channels: Int, depth: Int, mode: Int, planes: [Data]) -> Data {
        var data = Data("8BPS".utf8)
        func u16(_ value: Int) {
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8(value & 0xff))
        }
        func u32(_ value: Int) {
            data.append(UInt8((value >> 24) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8(value & 0xff))
        }
        u16(1)
        data.append(Data(count: 6))
        u16(channels)
        u32(height)
        u32(width)
        u16(depth)
        u16(mode)
        u32(0)          // color mode data
        u32(0)          // image resources
        u32(0)          // layer and mask info
        u16(0)          // image data, uncompressed
        for plane in planes { data.append(plane) }
        return data
    }

    private func plane8(width: Int, height: Int, _ value: (Int, Int) -> UInt8) -> Data {
        var data = Data()
        for y in 0..<height { for x in 0..<width { data.append(value(x, y)) } }
        return data
    }

    private func plane16(width: Int, height: Int, _ value: (Int, Int) -> UInt16) -> Data {
        var data = Data()
        for y in 0..<height {
            for x in 0..<width {
                let sample = value(x, y)
                data.append(UInt8(sample >> 8))
                data.append(UInt8(sample & 0xff))
            }
        }
        return data
    }

    private func plane32(width: Int, height: Int, _ value: (Int, Int) -> Float) -> Data {
        var data = Data()
        for y in 0..<height {
            for x in 0..<width { withUnsafeBytes(of: value(x, y).bitPattern.bigEndian) { data.append(contentsOf: $0) } }
        }
        return data
    }

    private func temporary(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).psd")
        try data.write(to: url)
        return url
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

    @Test func sixteenBitRGBComesInAsItsMergedImage() async throws {
        let width = 4, height = 2
        let data = flattened(width: width, height: height, channels: 3, depth: 16, mode: 3, planes: [
            plane16(width: width, height: height) { x, _ in UInt16(x * 16_000) },
            plane16(width: width, height: height) { _, y in UInt16(y * 32_000) },
            plane16(width: width, height: height) { _, _ in 32_768 },
        ])
        let parsed = try PSDReader.read(data)
        #expect(parsed.sourceDepth == 16)
        #expect(parsed.layers.isEmpty, "a flattened file has no layer records")

        let asset = try await ImageImporter.shared.decode(try temporary(data), flattenedPhotoshop: true)
        #expect(asset.image.width == width && asset.image.height == height)
        // 16-bit samples come down to their high byte: x = 3 is 48000/65535, y = 1 is 32000/65535.
        let sample = try pixel(asset.image, x: 3, y: 1)
        #expect(abs(sample.r - 187) <= 2, "red was \(sample.r)")
        #expect(abs(sample.g - 125) <= 2, "green was \(sample.g)")
        #expect(abs(sample.b - 128) <= 2, "blue was \(sample.b)")
    }

    @Test func thirtyTwoBitRGBComesInAsItsMergedImage() async throws {
        let width = 4, height = 2
        let data = flattened(width: width, height: height, channels: 3, depth: 32, mode: 3, planes: [
            plane32(width: width, height: height) { x, _ in Float(x) / 15 },
            plane32(width: width, height: height) { _, y in Float(y) / 15 },
            plane32(width: width, height: height) { _, _ in 0.5 },
        ])
        #expect(try PSDReader.read(data).sourceDepth == 32)
        let asset = try await ImageImporter.shared.decode(try temporary(data), flattenedPhotoshop: true)
        let sample = try pixel(asset.image, x: 3, y: 1)
        #expect(abs(sample.r - 51) <= 3, "red was \(sample.r)")
        #expect(abs(sample.g - 17) <= 3, "green was \(sample.g)")
        #expect(abs(sample.b - 128) <= 3, "blue was \(sample.b)")
    }

    @Test func CMYKComesInAsItsMergedImage() async throws {
        let width = 4, height = 2
        // Photoshop stores CMYK with 255 for no ink, so this writes the ink ramp inverted. The values
        // were checked against a file the system's own writer produced, which PIL reads the same way.
        let data = flattened(width: width, height: height, channels: 4, depth: 8, mode: 4, planes: [
            plane8(width: width, height: height) { _, _ in 255 },
            plane8(width: width, height: height) { _, _ in 255 },
            plane8(width: width, height: height) { _, _ in 255 },
            plane8(width: width, height: height) { x, _ in UInt8(255 - x * 60) },
        ])
        #expect(try PSDReader.read(data).isCMYK)
        let asset = try await ImageImporter.shared.decode(try temporary(data), flattenedPhotoshop: true)
        #expect(asset.image.width == width && asset.image.height == height)
        // No ink at the left edge comes through as white; more black ink makes it darker.
        let white = try pixel(asset.image, x: 0, y: 0)
        #expect(white.r > 240 && white.g > 240 && white.b > 240, "no ink should be white, was \(white)")
        let inked = try pixel(asset.image, x: 3, y: 0)
        #expect(inked.r < white.r - 60, "more ink should be darker, was \(inked)")
    }

    @Test func anEightBitRGBFileStillComesInAsLayers() throws {
        // The fallback must not swallow the files the reader does handle.
        let data = flattened(width: 2, height: 2, channels: 3, depth: 8, mode: 3, planes: [
            plane8(width: 2, height: 2) { _, _ in 10 },
            plane8(width: 2, height: 2) { _, _ in 20 },
            plane8(width: 2, height: 2) { _, _ in 30 },
        ])
        let parsed = try PSDReader.read(data)
        #expect(parsed.layers.isEmpty)
    }

    @Test func theReportSaysWhatWasConverted() {
        let url = URL(fileURLWithPath: "/tmp/Night Sky.psd")

        let depth = EditorSession.rasterConversionNotes(for: url, error: .unsupportedDepth(16))
        #expect(depth.count == 1)
        #expect(depth[0].layerName == "Night Sky")
        #expect(depth[0].message.contains("16-bit"))
        #expect(depth[0].message.contains("no longer editable"))

        let mode = EditorSession.rasterConversionNotes(for: url, error: .unsupportedColorMode(4))
        #expect(mode.count == 1)
        #expect(mode[0].message.contains("CMYK"))
        #expect(mode[0].message.contains("no longer editable"))

        // Compression the coder doesn't unpack still comes in, and says so.
        let compression = EditorSession.rasterConversionNotes(for: url, error: .unsupportedCompression)
        #expect(compression.count == 1)
        #expect(compression[0].message.contains("layers are no longer editable"))

        // Other reader errors are failures, not conversions, so they report nothing.
        #expect(EditorSession.rasterConversionNotes(for: url, error: .truncated).isEmpty)
        #expect(EditorSession.rasterConversionNotes(for: url, error: .unsupportedVersion).isEmpty)
    }
}
