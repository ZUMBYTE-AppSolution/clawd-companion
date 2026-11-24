import AppKit
import CoreText
import XCTest
@testable import ClawdCompanion

final class ClawdVoiceTests: XCTestCase {
    func testLanguageMatchingAvoidsWrongLanguageAndWrongChineseVariety() async {
        await MainActor.run {
            XCTAssertGreaterThan(ClawdVoice.match("de-DE", to: "de-DE") ?? 0, ClawdVoice.match("de-AT", to: "de-DE") ?? 0)
            XCTAssertNotNil(ClawdVoice.match("en-US", to: "en"))
            XCTAssertNotNil(ClawdVoice.match("zh-CN", to: "zh-Hans"))
            XCTAssertNotNil(ClawdVoice.match("ur-PK", to: "ur"))
            XCTAssertNil(ClawdVoice.match("ar-SA", to: "ur"))
            XCTAssertNil(ClawdVoice.match("en-GB", to: "bn"))
            XCTAssertNil(ClawdVoice.match("zh-HK", to: "zh-Hans"))
            XCTAssertNil(ClawdVoice.match("zh-TW", to: "zh-Hans"))
            let voice = ClawdVoice()
            XCTAssertFalse(voice.enabled)
            voice.speak("Silent verification", language: "en")
            voice.stop()
        }
    }

    func testComplexScriptsShapeToAvailableGlyphsAndRTLAlignsToRight() async throws {
        try await MainActor.run {
            for (language, text, rtl) in [
                ("ar", "هل تسمح لـ Claude بالمتابعة؟", true),
                ("ur", "کیا آپ اجازت دیتے ہیں؟", true),
                ("hi", "क्या मैं आगे बढ़ूँ?", false),
                ("bn", "আমি কি এগিয়ে যেতে পারি?", false),
                ("zh-Hans", "允许继续吗？", false),
                ("es", "¿Puedo continuar?", false)
            ] {
                let paragraph = PixelDialogue.paragraph(text, language: language, rightToLeft: rtl, color: .white)
                let style = try XCTUnwrap(paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(style.alignment, rtl ? .right : .natural)
                let line = CTLineCreateWithAttributedString(paragraph)
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                let rtlRuns = runs.filter { CTRunGetStatus($0).contains(.rightToLeft) }
                XCTAssertEqual(!rtlRuns.isEmpty, rtl)
                var glyphTotal = 0
                for run in runs {
                    var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    XCTAssertFalse(glyphs.contains(0), "Missing glyph in \(language)")
                    glyphTotal += glyphs.count
                }
                XCTAssertGreaterThan(glyphTotal, 3)
            }
        }
    }

    func testNoticePreservesJoinersAndVoiceOverGetsOriginalText() async throws {
        try await MainActor.run {
            let original = "👩‍💻 क्‍ष پیش‌فرض"
            let notice = try XCTUnwrap(SpeechNotice(title: "Claude.ai", message: original, kind: "info"))
            XCTAssertEqual(notice.message, original)
            let canvas = SpeechCanvas()
            canvas.setNotice(notice)
            XCTAssertEqual(canvas.accessibilityLabel(), "Claude.ai. " + original)
            let size = canvas.bodySize(for: CGSize(width: 800, height: 600))
            XCTAssertGreaterThanOrEqual(size.width, 128)
            XCTAssertGreaterThan(size.height, 42)
        }
    }
}
