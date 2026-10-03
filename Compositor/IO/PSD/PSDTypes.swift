import CoreGraphics
import Foundation
import UniformTypeIdentifiers

nonisolated enum PSDError: LocalizedError, Equatable {
    case truncated, unsupportedVersion
    /// Bits per channel, as the file declares it: 1, 8, 16 or 32.
    case unsupportedDepth(Int)
    /// Photoshop's color mode value: 0 bitmap, 1 grayscale, 2 indexed, 3 RGB, 4 CMYK, 7 multichannel,
    /// 8 duotone, 9 Lab.
    case unsupportedColorMode(Int)
    case unsupportedCompression

    /// True for the files the reader can't take but Photoshop's own merged image can supply: a color
    /// mode other than RGB and CMYK, a bit depth other than 8, 16 or 32, or layer compression the
    /// coder doesn't unpack. The importer reads those as pixels instead of failing.
    var requiresRasterImport: Bool {
        switch self {
        case .unsupportedDepth, .unsupportedColorMode, .unsupportedCompression: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .truncated: String(localized: "The Photoshop file could not be read. It may be damaged or incomplete.")
        case .unsupportedVersion: String(localized: "This Photoshop file uses a format version Compositor can’t read.")
        case .unsupportedDepth(let bits):
            String(localized: "This Photoshop file is \(bits)-bit, and its merged image couldn’t be read. Convert it to 8-bit RGB in Photoshop, then import it again.")
        case .unsupportedColorMode(let mode):
            String(localized: "This Photoshop file is \(psdColorModeName(mode)), and its merged image couldn’t be read. Convert it to RGB in Photoshop, then import it again.")
        case .unsupportedCompression: String(localized: "This Photoshop file uses a layer compression method that isn’t supported.")
        }
    }
}

/// The name Photoshop gives a color mode, for a message the reader can act on. RGB needs no name
/// here: it is the mode the reader reads.
nonisolated func psdColorModeName(_ mode: Int) -> String {
    switch mode {
    case 0: String(localized: "Bitmap")
    case 1: String(localized: "Grayscale")
    case 2: String(localized: "Indexed Color")
    case 4: String(localized: "CMYK")
    case 7: String(localized: "Multichannel")
    case 8: String(localized: "Duotone")
    case 9: String(localized: "Lab")
    default: String(localized: "not RGB")
    }
}

nonisolated struct PSDConversion: Identifiable, Equatable, Sendable {
    let id: UUID
    let layerName: String
    let message: String
    init(id: UUID = UUID(), layerName: String, message: String) {
        self.id = id
        self.layerName = layerName
        self.message = message
    }
}

nonisolated struct PSDDocument: @unchecked Sendable {
    var width: Int
    var height: Int
    var resolution: Double
    /// Bottom to top, including folders. Hidden section dividers are not stored.
    var layers: [PSDRecord]
    /// The file's bits per channel, so the report can say when it was reduced to 8.
    var sourceDepth = 8
    /// The file is CMYK, so its layers were converted to sRGB on the way in.
    var isCMYK = false
}

nonisolated struct PSDRecord: @unchecked Sendable {
    var id: UUID
    var parentID: UUID?
    var name: String
    var isGroup = false
    var isVisible = true
    var opacity: Double = 1
    var blendKey = "norm"
    var clipping = false
    var croppedToCanvas = false
    var bounds = CGRect.zero
    var image: CGImage?
    var mask: CGImage?
    /// Where `mask` sits on the document, and the value everywhere outside it: Photoshop stores only the part of a
    /// mask that isn't that default.
    var maskBounds = CGRect.zero
    var maskDefault: UInt8 = 255
    var maskEnabled = true
    var maskLinked = true
    var adjustment: LayerAdjustment?
    var kind = PSDLayerKind.raster
    var shape: LayerShapeStyle?
    var shapeNotes: [String] = []
    /// Parsed Photoshop type, when the `TySh` block maps onto an editable text layer.
    var text: PSDText.Source?
}

nonisolated enum PSDLayerKind: Equatable, Sendable {
    case raster, group, adjustment, text, smartObject, effects, vector, other
}

extension LayerBlendMode {
    nonisolated static func fromPSD(_ key: String) -> LayerBlendMode? {
        switch key {
        case "norm": .normal
        case "mul ": .multiply
        case "scrn": .screen
        case "over": .overlay
        case "sLit": .softLight
        case "dark": .darken
        case "lite": .lighten
        case "diff": .difference
        case "div ": .colorDodge
        case "idiv": .colorBurn
        case "hue ": .hue
        case "sat ": .saturation
        case "colr": .color
        case "lum ": .luminosity
        case "lbrn": .linearBurn
        case "lddg": .linearDodge
        case "hLit": .hardLight
        case "vLit": .vividLight
        case "lLit": .linearLight
        case "pLit": .pinLight
        case "hMix": .hardMix
        case "smud": .exclusion
        case "fsub": .subtract
        case "fdiv": .divide
        // Dissolve, Darker Color and Lighter Color are deliberately absent: Compositor has no
        // equivalent, so they fall through to Normal and say so in the conversion report.
        default: nil
        }
    }
}

extension PSDRecord {
    nonisolated var blendMode: LayerBlendMode? { LayerBlendMode.fromPSD(blendKey) }
}
