import AppKit
import Foundation
import Testing
@testable import disk_hog

struct LocalizationTests {
    @Test(
        "Ships each supported localization",
        arguments: [
            ("de", "Wählen Sie den zu scannenden Ordner"),
            ("fr", "Choisissez le dossier à analyser"),
            ("es", "Elija la carpeta para escanear"),
            ("it", "Scegli la cartella da scansionare"),
        ]
    )
    func shipsLocalization(language: String, expectedTranslation: String) throws {
        let localizationURL: URL = try #require(
            Bundle.main.url(forResource: language, withExtension: "lproj")
        )
        let localizedBundle: Bundle = try #require(Bundle(url: localizationURL))

        let translation: String = localizedBundle.localizedString(
            forKey: "Choose Folder to Scan",
            value: nil,
            table: nil
        )

        #expect(translation == expectedTranslation)
    }

    @Test func catalogEntriesIncludeEverySupportedLanguage() throws {
        let catalog: [String: Any] = try Self.catalogStrings()
        let supportedLanguages: Set<String> = ["de", "es", "fr", "it"]
        let incompleteEntries: [String] = catalog.compactMap { key, value in
            guard let entry: [String: Any] = value as? [String: Any],
                  let localizations: [String: Any] = entry["localizations"] as? [String: Any] else {
                return "\(key): missing localizations"
            }
            let presentLanguages: Set<String> = Set(localizations.keys).intersection(supportedLanguages)
            return presentLanguages == supportedLanguages
                ? nil
                : "\(key): missing \(supportedLanguages.subtracting(presentLanguages).sorted().joined(separator: ", "))"
        }

        #expect(incompleteEntries.isEmpty)
    }

    @Test func translationsAreCompleteAndPreserveFormatArguments() throws {
        let catalog = try Self.catalogStrings()
        let format = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:lld|llu|ld|lu|@|d|u|f)"#)
        func arguments(_ value: String) -> [String] {
            let value = value.replacingOccurrences(of: "%%", with: "")
            return format.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                let token = String(value[Range($0.range, in: value)!])
                return token.replacingOccurrences(of: #"[0-9]+\$"#, with: "", options: .regularExpression)
            }.sorted()
        }
        func units(_ value: Any) -> [[String: String]] {
            guard let object = value as? [String: Any] else { return [] }
            if let unit = object["stringUnit"] as? [String: String] { return [unit] }
            return object.values.flatMap { units($0) }
        }
        for (key, entry) in catalog {
            let entry = try #require(entry as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in ["de", "es", "fr", "it"] {
                let translatedUnits = units(localizations[language] ?? [:])
                #expect(!translatedUnits.isEmpty, "Missing translation: \(language), \(key)")
                for unit in translatedUnits {
                    let value = try #require(unit["value"])
                    #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    #expect(unit["state"] == "translated", "Unfinished: \(language), \(key)")
                    #expect(arguments(value) == arguments(key), "Format arguments: \(language), \(key)")
                }
            }
        }
    }

    @Test func countLabelsShipSingularAndPluralForms() throws {
        for language in ["en", "de", "es", "fr", "it"] {
            let url = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
            let bundle = try #require(Bundle(url: url))
            for key in ["%lld items", "%lld files"] {
                let format = bundle.localizedString(forKey: key, value: nil, table: nil)
                let singular = String.localizedStringWithFormat(format, Int64(1))
                let plural = String.localizedStringWithFormat(format, Int64(2))
                #expect(singular.contains("1"))
                #expect(plural.contains("2"))
                if !(language == "it" && key == "%lld files") {
                    #expect(singular.replacingOccurrences(of: "1", with: "") != plural.replacingOccurrences(of: "2", with: ""))
                }
            }
        }
    }

    @Test func staticUserFacingLiteralsAppearInStringCatalog() throws {
        let catalogKeys: Set<String> = try Self.catalogKeys()
        let patterns: [SourceLiteralPattern] = [
            SourceLiteralPattern(name: "String(localized:)", pattern: #"String\s*\(\s*localized:\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "Text", pattern: #"\bText\(\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "Button", pattern: #"\bButton\(\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "Label", pattern: #"\bLabel\(\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "ContentUnavailableView", pattern: #"\bContentUnavailableView\(\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "accessibilityLabel", pattern: #"\.accessibilityLabel\(\s*"((?:\\.|[^"\\])*)""#),
        ]
        let missingKeys: [String] = try Self.sourceMatches(patterns: patterns).compactMap { match in
            guard !match.literal.contains(#"\("#),
                  !catalogKeys.contains(match.literal) else {
                return nil
            }
            return "\(match.location): \(match.patternName) literal “\(match.literal)” is missing from Localizable.xcstrings"
        }

        #expect(missingKeys.isEmpty)
    }

    @Test func appKitUserFacingStringArgumentsAreExplicitlyLocalized() throws {
        let patterns: [SourceLiteralPattern] = [
            SourceLiteralPattern(name: "NSMenuItem title", pattern: #"NSMenuItem\(\s*title:\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "NSAlert button title", pattern: #"\.addButton\(\s*withTitle:\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "NSAlert message text", pattern: #"\.messageText\s*=\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "NSAlert informative text", pattern: #"\.informativeText\s*=\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "AppKit title", pattern: #"\.title\s*=\s*"((?:\\.|[^"\\])*)""#),
            SourceLiteralPattern(name: "AppKit tooltip", pattern: #"\.toolTip\s*=\s*"((?:\\.|[^"\\])*)""#),
        ]
        let rawAppKitLiterals: [String] = try Self.sourceMatches(patterns: patterns).map { match in
            "\(match.location): \(match.patternName) uses raw literal “\(match.literal)”; wrap it in String(localized:)"
        }

        #expect(rawAppKitLiterals.isEmpty)
    }

    private static func catalogKeys() throws -> Set<String> {
        Set(try catalogStrings().keys)
    }

    private static func catalogStrings() throws -> [String: Any] {
        let catalogURL: URL = projectRoot.appendingPathComponent("disk_hog/Localizable.xcstrings")
        let data: Data = try Data(contentsOf: catalogURL)
        let object: Any = try JSONSerialization.jsonObject(with: data)
        let catalog: [String: Any] = try #require(object as? [String: Any])
        return try #require(catalog["strings"] as? [String: Any])
    }

    private static func sourceMatches(
        patterns: [SourceLiteralPattern]
    ) throws -> [SourceLiteralMatch] {
        let sourceRoot: URL = projectRoot.appendingPathComponent("disk_hog")
        let sourceFiles: [URL] = try swiftSourceFiles(in: sourceRoot)
        var matches: [SourceLiteralMatch] = []
        for sourceFile: URL in sourceFiles {
            let source: String = try String(contentsOf: sourceFile, encoding: .utf8)
            for literalPattern: SourceLiteralPattern in patterns {
                let expression: NSRegularExpression = try NSRegularExpression(
                    pattern: literalPattern.pattern
                )
                let range: NSRange = NSRange(source.startIndex..<source.endIndex, in: source)
                for match: NSTextCheckingResult in expression.matches(in: source, range: range) {
                    guard let literalRange: Range<String.Index> = Range(match.range(at: 1), in: source),
                          let literal: String = decodeSwiftStaticStringLiteral(String(source[literalRange])) else {
                        continue
                    }
                    matches.append(SourceLiteralMatch(
                        patternName: literalPattern.name,
                        literal: literal,
                        location: sourceLocation(in: sourceFile, source: source, matchRange: match.range)
                    ))
                }
            }
        }
        return matches.sorted { $0.location < $1.location }
    }

    private static func decodeSwiftStaticStringLiteral(_ literal: String) -> String? {
        guard !literal.contains(#"\("#) else {
            return literal
        }
        let jsonLiteral: String = "\"\(literal)\""
        return try? JSONDecoder().decode(String.self, from: Data(jsonLiteral.utf8))
    }

    private static func swiftSourceFiles(in root: URL) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator: FileManager.DirectoryEnumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
        )
        return enumerator.compactMap { entry in
            guard let url: URL = entry as? URL,
                  url.pathExtension == "swift",
                  (try? url.resourceValues(forKeys: Set(resourceKeys)).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private static func sourceLocation(
        in fileURL: URL,
        source: String,
        matchRange: NSRange
    ) -> String {
        let line: Int = source.utf16.prefix(matchRange.location).filter { $0 == 10 }.count + 1
        let relativePath: String = fileURL.path.replacingOccurrences(
            of: projectRoot.path + "/",
            with: ""
        )
        return "\(relativePath):\(line)"
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct SourceLiteralPattern {
    let name: String
    let pattern: String
}

private struct SourceLiteralMatch {
    let patternName: String
    let literal: String
    let location: String
}

struct AppearanceSupportTests {
    @Test func doesNotOptOutOfSystemAppearance() {
        let requiresAqua: Bool =
            Bundle.main.object(forInfoDictionaryKey: "NSRequiresAquaSystemAppearance")
                as? Bool ?? false

        #expect(requiresAqua == false)
    }

    @Test(
        "Semantic application colors adapt to system appearance",
        arguments: [
            NSColor.windowBackgroundColor,
            NSColor.controlBackgroundColor,
            NSColor.textBackgroundColor,
            NSColor.labelColor,
        ]
    )
    func semanticColorAdapts(color: NSColor) throws {
        let lightColor: NSColor = try resolvedColor(
            color,
            appearanceName: .aqua
        )
        let darkColor: NSColor = try resolvedColor(
            color,
            appearanceName: .darkAqua
        )

        #expect(lightColor != darkColor)
    }

    private func resolvedColor(
        _ color: NSColor,
        appearanceName: NSAppearance.Name
    ) throws -> NSColor {
        let appearance: NSAppearance = try #require(
            NSAppearance(named: appearanceName)
        )
        var resolvedColor: NSColor?

        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.deviceRGB)
        }

        return try #require(resolvedColor)
    }
}
