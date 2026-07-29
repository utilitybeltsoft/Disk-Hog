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
