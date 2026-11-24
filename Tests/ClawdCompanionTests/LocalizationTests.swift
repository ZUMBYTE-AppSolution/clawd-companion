import XCTest
@testable import ClawdCompanion

final class LocalizationTests: XCTestCase {
    func testEveryBundledPhraseHasAllTranslationsAndTheSamePlaceholders() throws {
        let dir = try XCTUnwrap(L10n.directory)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tsv" }
        XCTAssertTrue(Set(files.map { $0.deletingPathExtension().lastPathComponent })
            .isSuperset(of: ["Companion", "Overview", "Settings", "Desktop"]))
        let codes = L10n.choices.map(\.0)
        let marker = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ s: String) -> [String] {
            marker.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .compactMap { Range($0.range, in: s).map { String(s[$0]) } }.sorted()
        }
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline)
            XCTAssertEqual(lines.first?.components(separatedBy: "\t"), codes)
            for row in lines.dropFirst() {
                let cells = row.components(separatedBy: "\t")
                XCTAssertEqual(cells.count, codes.count, String(row.prefix(60)))
                let keys = placeholders(cells[0])
                for cell in cells.dropFirst() {
                    XCTAssertFalse(cell.trimmingCharacters(in: .whitespaces).isEmpty, cells[0])
                    XCTAssertEqual(placeholders(cell), keys, cells[0])
                }
            }
        }
        for language in codes.dropFirst() {
            for key in ["Sprache", "Sitzt auf der Titelleiste", "Wartet auf deine Freigabe", "Aktionsvorschau"] {
                XCTAssertNotEqual(L10n.text(key, in: language), key)
            }
        }
    }

    func testLocaleMatchingAndSubstitution() {
        XCTAssertEqual(L10n.resolve("system", preferred: ["sv-SE", "zh-TW"]), "zh-Hans")
        XCTAssertEqual(L10n.resolve("pt_BR"), "pt")
        XCTAssertEqual(L10n.resolve("ur-PK"), "ur")
        XCTAssertEqual(L10n.resolve("in-ID"), "id")
        XCTAssertEqual(L10n.resolve("system", preferred: ["sv"]), "en")
        XCTAssertEqual(L10n.text("{1} {0}", in: "de", values: ["Start", "{0}"]), "{0} Start")
    }
}
