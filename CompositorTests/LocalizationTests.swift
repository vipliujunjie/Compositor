import Foundation
import Testing

/// The interface ships in English and Simplified Chinese. English needs no catalog entries, because
/// the key is the English text itself, so these tests guard the translated side and the pipeline
/// that puts it in the app bundle. `Compositor/Localizable.xcstrings` is the source of both.
@Suite("Localization")
struct LocalizationTests {
    /// The compiled catalog of the language the app ships as a translation.
    private static func chineseCatalog() -> [String: String]? {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: "zh-Hans"),
              let entries = NSDictionary(contentsOfFile: path) as? [String: String] else { return nil }
        return entries
    }

    /// Format specifiers, in a form that survives reordering: `%@`, `%lld`, `%1$@`, `%%`.
    private static let placeholderPattern = try? NSRegularExpression(
        pattern: "%(?:[0-9]+\\$)?(?:@|lld|ld|d|f|\\.\\d+f|%)")

    private static func placeholders(_ text: String) -> [String] {
        guard let placeholderPattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return placeholderPattern.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    @Test func shipsSimplifiedChinese() {
        #expect(Bundle.main.localizations.contains("zh-Hans"),
                "the built app declares the Chinese localization")
    }

    @Test func translatesTheInterface() throws {
        let catalog = try #require(Self.chineseCatalog(), "the bundle carries a compiled zh-Hans catalog")
        #expect(catalog.count > 900, "the translation covers the interface, not a sample of it")

        // Names a Chinese reader of Photoshop expects, plus one interpolated key.
        #expect(catalog["Layer"] == "图层")
        #expect(catalog["Drop Shadow"] == "投影")
        #expect(catalog["Black & White"] == "黑白")
        #expect(catalog["Undo %@"] == "撤销 %@")
    }

    /// A translation that drops or reorders a placeholder crashes at runtime, so the catalog is
    /// checked as a whole rather than one string at a time.
    @Test func keepsPlaceholdersIntact() throws {
        let catalog = try #require(Self.chineseCatalog())
        for (key, value) in catalog where key.contains("%") {
            #expect(Self.placeholders(key) == Self.placeholders(value),
                    "\(key) keeps its placeholders, got \(value)")
        }
    }

    /// A translated string that still reads as English usually means an entry was copied rather
    /// than translated. The exceptions are names the glossary keeps in English on purpose.
    @Test func leavesNoEnglishSentences() throws {
        let catalog = try #require(Self.chineseCatalog())
        let kept = ["Camera", "Raw", "Compositor", "Photoshop", "Upright", "Instagram", "YouTube",
                    "MacBook", "iPhone", "Studio", "Display", "Return", "Enter", "Esc", "Escape",
                    "Tab", "Space", "Delete", "Backspace", "Option", "Shift", "Command", "Control",
                    "sRGB", "RGB", "CMYK", "HDR", "PNG", "JPEG", "TIFF", "SVG", "PSD", "PSB", "HEIC",
                    "RAW", "EXIF", "GPU", "Metal", "Alpha", "Hex", "ASCII", "EV", "macOS", "Finder",
                    "Atkinson", "Bayer", "Floyd", "Steinberg", "Halftone", "Scanline", "Diamond"]
        let words = try NSRegularExpression(pattern: "[A-Za-z]{2,}")
        let strip = try #require(Self.placeholderPattern)
        var suspects: [String] = []
        for (key, value) in catalog {
            // Placeholders are not words: `%lld` would otherwise count as one.
            let text = strip.stringByReplacingMatches(
                in: value, range: NSRange(value.startIndex..., in: value), withTemplate: " ")
            let range = NSRange(text.startIndex..., in: text)
            let found = words.matches(in: text, range: range)
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { !kept.contains($0) }
            // Two or more Latin words in a value for a sentence-length key means it was not translated.
            if found.count >= 2, key.count > 24, key.contains(" ") { suspects.append("\(key) → \(value)") }
        }
        #expect(suspects.isEmpty, "untranslated entries: \(suspects.prefix(5))")
    }
}
