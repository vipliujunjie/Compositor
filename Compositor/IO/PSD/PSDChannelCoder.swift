import CoreGraphics
import Foundation

nonisolated struct PSDCrop: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// Unpacks Photoshop layer channels from Adobe’s 2019 Photoshop File Formats
/// Specification (Image Data, compression 0 raw and 1 PackBits).
nonisolated enum PSDChannelCoder {
    static func decode(compression: Int, width: Int, height: Int, depth: Int = 8, data: Data,
                       largeDocument: Bool = false, crop: PSDCrop? = nil) throws -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        guard depth == 8 || depth == 16 || depth == 32 else { throw PSDError.unsupportedDepth(depth) }
        let sampleBytes = depth / 8
        let payload = [UInt8](data)
        let decoded: [UInt8]
        guard let crop else {
            decoded = try decodeFull(compression: compression, width: width, height: height,
                                     sampleBytes: sampleBytes, data: payload, largeDocument: largeDocument)
            return reduced(decoded, depth: depth)
        }
        guard crop.x >= 0, crop.y >= 0, crop.width >= 0, crop.height >= 0,
              crop.x + crop.width <= width, crop.y + crop.height <= height else { throw PSDError.truncated }
        guard crop.width > 0, crop.height > 0 else { return [] }
        switch compression {
        case 0:
            decoded = try cropRaw(width: width, height: height, sampleBytes: sampleBytes, data: payload, crop: crop)
        case 1:
            decoded = try unpackRLE(width: width, height: height, sampleBytes: sampleBytes, data: payload,
                                    largeDocument: largeDocument, crop: crop)
        default:
            throw PSDError.unsupportedCompression
        }
        return reduced(decoded, depth: depth)
    }

    /// One byte per sample, which is what the rest of the reader works in: a 16-bit sample keeps its
    /// high byte, and a 32-bit one — Photoshop stores those as big-endian floats in 0...1 — is scaled.
    private static func reduced(_ samples: [UInt8], depth: Int) -> [UInt8] {
        switch depth {
        case 16:
            return stride(from: 0, to: samples.count, by: 2).map { samples[$0] }
        case 32:
            var reduced = [UInt8](repeating: 0, count: samples.count / 4)
            for i in 0..<reduced.count {
                let bits = UInt32(samples[i * 4]) << 24 | UInt32(samples[i * 4 + 1]) << 16
                    | UInt32(samples[i * 4 + 2]) << 8 | UInt32(samples[i * 4 + 3])
                let value = Float(bitPattern: bits)
                let scaled = (value.isFinite ? value : 0) * 255
                reduced[i] = UInt8(max(0, min(255, scaled.rounded())))
            }
            return reduced
        default:
            return samples
        }
    }

    private static func decodeFull(compression: Int, width: Int, height: Int, sampleBytes: Int,
                                   data: [UInt8], largeDocument: Bool) throws -> [UInt8] {
        let expected = width * height * sampleBytes
        switch compression {
        case 0:
            guard data.count >= expected else { throw PSDError.truncated }
            return Array(data.prefix(expected))
        case 1:
            return try unpackRLE(width: width, height: height, sampleBytes: sampleBytes, data: data,
                                 largeDocument: largeDocument)
        default:
            throw PSDError.unsupportedCompression
        }
    }

    private static func cropRaw(width: Int, height: Int, sampleBytes: Int, data: [UInt8], crop: PSDCrop) throws -> [UInt8] {
        guard data.count >= width * height * sampleBytes else { throw PSDError.truncated }
        let sourceRow = width * sampleBytes
        let cropBytes = crop.width * sampleBytes
        var plane = [UInt8](repeating: 0, count: cropBytes * crop.height)
        for row in 0..<crop.height {
            let sourceStart = (crop.y + row) * sourceRow + crop.x * sampleBytes
            let targetStart = row * cropBytes
            plane.replaceSubrange(targetStart..<(targetStart + cropBytes),
                                  with: data[sourceStart..<(sourceStart + cropBytes)])
        }
        return plane
    }

    static func rgbaImage(width: Int, height: Int, red: [UInt8], green: [UInt8], blue: [UInt8], alpha: [UInt8]) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let count = width * height
        for i in 0..<count {
            let a = alpha[i]
            pixels[i * 4] = UInt8((UInt16(red[i]) * UInt16(a) + 127) / 255)
            pixels[i * 4 + 1] = UInt8((UInt16(green[i]) * UInt16(a) + 127) / 255)
            pixels[i * 4 + 2] = UInt8((UInt16(blue[i]) * UInt16(a) + 127) / 255)
            pixels[i * 4 + 3] = a
        }
        return try image(width: width, height: height, rgba: pixels)
    }

    static func image(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        let bytesPerRow = width * 4
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw PSDError.truncated }
        return image
    }

    /// A CMYK layer's pixels, converted to the sRGB working space by drawing them through a CMYK
    /// color space — the profile Photoshop embedded, when there is one — with the layer's alpha
    /// clipping the drawing, which leaves the pixels premultiplied the way `rgbaImage` builds them.
    /// The ink planes hold ink amounts: 0 is no ink.
    static func cmykImage(width: Int, height: Int, cyan: [UInt8], magenta: [UInt8], yellow: [UInt8],
                          key: [UInt8], alpha: [UInt8], profile: CGColorSpace?) throws -> CGImage {
        let count = width * height
        guard cyan.count >= count, magenta.count >= count, yellow.count >= count,
              key.count >= count, alpha.count >= count else { throw PSDError.truncated }
        var ink = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let target = i * 4
            ink[target] = cyan[i]
            ink[target + 1] = magenta[i]
            ink[target + 2] = yellow[i]
            ink[target + 3] = key[i]
        }
        guard let inkProvider = CGDataProvider(data: Data(ink) as CFData),
              let cmyk = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: profile ?? CGColorSpaceCreateDeviceCMYK(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: inkProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let alphaProvider = CGDataProvider(data: Data(alpha) as CFData),
              // CoreGraphics reads a gray mask as its own inverse, so the decode array turns the
              // layer's alpha into coverage rather than 255 minus coverage.
              let mask = CGImage(
                maskWidth: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                provider: alphaProvider, decode: [1, 0], shouldInterpolate: false),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw PSDError.truncated }
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: mask)
        context.draw(cmyk, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let converted = context.makeImage() else { throw PSDError.truncated }
        return converted
    }

    static func maskImage(width: Int, height: Int, gray: [UInt8]) throws -> CGImage {
        let data = Data(gray)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw PSDError.truncated }
        return image
    }

    private static func unpackRLE(width: Int, height: Int, sampleBytes: Int, data: [UInt8], largeDocument: Bool) throws -> [UInt8] {
        let rowBytes = width * sampleBytes
        var offset = 0
        func next() throws -> UInt8 {
            guard offset < data.count else { throw PSDError.truncated }
            defer { offset += 1 }
            return data[offset]
        }
        var counts = [Int](repeating: 0, count: height)
        for row in 0..<height {
            if largeDocument {
                let a = try next(), b = try next(), c = try next(), d = try next()
                counts[row] = Int(UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d))
            } else {
                let hi = try next(), lo = try next()
                counts[row] = Int(hi) << 8 | Int(lo)
            }
        }
        var plane = [UInt8](repeating: 0, count: rowBytes * height)
        for row in 0..<height {
            let end = offset + counts[row]
            guard end <= data.count else { throw PSDError.truncated }
            var written = 0
            while written < rowBytes {
                guard offset < end else { throw PSDError.truncated }
                let n = Int8(bitPattern: data[offset])
                offset += 1
                if n >= 0 {
                    let count = Int(n) + 1
                    guard written + count <= rowBytes, offset + count <= end else { throw PSDError.truncated }
                    for i in 0..<count { plane[row * rowBytes + written + i] = data[offset + i] }
                    offset += count
                    written += count
                } else if n != -128 {
                    let count = 1 - Int(n)
                    guard written + count <= rowBytes, offset < end else { throw PSDError.truncated }
                    let value = data[offset]
                    offset += 1
                    for i in 0..<count { plane[row * rowBytes + written + i] = value }
                    written += count
                }
            }
            offset = end
        }
        return plane
    }

    private static func unpackRLE(width: Int, height: Int, sampleBytes: Int, data: [UInt8], largeDocument: Bool, crop: PSDCrop) throws -> [UInt8] {
        let rowBytes = width * sampleBytes
        let cropBytes = crop.width * sampleBytes
        var offset = 0
        func next() throws -> UInt8 {
            guard offset < data.count else { throw PSDError.truncated }
            defer { offset += 1 }
            return data[offset]
        }
        var counts = [Int](repeating: 0, count: height)
        for row in 0..<height {
            if largeDocument {
                let a = try next(), b = try next(), c = try next(), d = try next()
                counts[row] = Int(UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d))
            } else {
                let hi = try next(), lo = try next()
                counts[row] = Int(hi) << 8 | Int(lo)
            }
        }
        var plane = [UInt8](repeating: 0, count: cropBytes * crop.height)
        var rowBuffer = [UInt8](repeating: 0, count: rowBytes)
        for row in 0..<height {
            let end = offset + counts[row]
            guard end <= data.count else { throw PSDError.truncated }
            guard row >= crop.y, row < crop.y + crop.height else {
                offset = end
                continue
            }
            var written = 0
            while written < rowBytes {
                guard offset < end else { throw PSDError.truncated }
                let n = Int8(bitPattern: data[offset])
                offset += 1
                if n >= 0 {
                    let count = Int(n) + 1
                    guard written + count <= rowBytes, offset + count <= end else { throw PSDError.truncated }
                    for index in 0..<count { rowBuffer[written + index] = data[offset + index] }
                    offset += count
                    written += count
                } else if n != -128 {
                    let count = 1 - Int(n)
                    guard written + count <= rowBytes, offset < end else { throw PSDError.truncated }
                    let value = data[offset]
                    offset += 1
                    for index in 0..<count { rowBuffer[written + index] = value }
                    written += count
                }
            }
            let targetStart = (row - crop.y) * cropBytes
            plane.replaceSubrange(targetStart..<(targetStart + cropBytes),
                                  with: rowBuffer[(crop.x * sampleBytes)..<((crop.x + crop.width) * sampleBytes)])
            offset = end
        }
        return plane
    }
}
