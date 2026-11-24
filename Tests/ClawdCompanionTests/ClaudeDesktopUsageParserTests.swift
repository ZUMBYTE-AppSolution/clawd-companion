import XCTest
@testable import ClawdCompanion

final class ClaudeDesktopUsageParserTests: XCTestCase {
    private let observed = ISO8601DateFormatter().date(from: "2026-11-24T09:00:00Z")!
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func parse(_ lines: [String], at date: Date? = nil) -> LimitReport? {
        ClaudeDesktopUsageParser.parse(lines, observedAt: date ?? observed, timeZone: berlin)
    }

    func testRealGermanDesktopSettingsCardsAndProductBreakdown() throws {
        let report = try XCTUnwrap(parse([
            "Aktuelle Sitzung", "Wird um 22:20 zurückgesetzt", "Aktuelle Sitzung", "4 % verwendet",
            "Diese Woche", "Zurücksetzung am Freitag, 21:00", "Diese Woche", "38 % verwendet",
            "Nutzung nach Produkt", "Claude Code", "61 %", "Chats", "38 %", "Cowork", "1 %"
        ]))
        XCTAssertEqual(report.session?.remaining, 96)
        XCTAssertEqual(report.week?.remaining, 62)
        XCTAssertEqual(report.session?.reset, ISO8601DateFormatter().date(from: "2026-11-24T21:20:00Z"))
        XCTAssertEqual(report.week?.reset, ISO8601DateFormatter().date(from: "2026-11-27T20:00:00Z"))
    }

    func testRealGermanDesktopPopoverAndOfficialClosedButton() throws {
        let report = try XCTUnwrap(parse([
            "5-Stunden-Limit", "Wird um 22:20 zurückgesetzt", "4 % genutzt",
            "Wöchentlich · alle Modelle", "Zurücksetzung am Fr., 21:00", "38 % genutzt"
        ]))
        let actual = "Nutzung: Wöchentlich · alle Modelle: 38%, Zurücksetzung am Fr., 21:00"
        let closed = try XCTUnwrap(ClaudeDesktopUsageParser.parseUsageButton(actual, observedAt: observed, timeZone: berlin))
        XCTAssertEqual(report.session?.remaining, 96)
        XCTAssertEqual(report.week?.remaining, 62)
        XCTAssertNil(closed.session)
        XCTAssertEqual(report.week, closed.week)
        XCTAssertEqual(closed.week?.resetLabel, "Zurücksetzung am Fr., 21:00")
        let english = "Usage: Weekly · All models: 38%, Resets Friday at 9:00 PM"
        let localized = ClaudeDesktopUsageParser.parseUsageButton(english, observedAt: observed, timeZone: berlin)
        XCTAssertEqual(localized?.week?.reset, closed.week?.reset)
        XCTAssertEqual(localized?.week?.remaining, 62)
        for other in ["Button, 38%", "Nutzung: Claude Code: 61%", "Nutzung: Wöchentlich · alle Modelle: 138%",
                      "Thread Nutzung: Wöchentlich · alle Modelle: 38%", "Usage: Weekly · all models: 38%, 29%",
                      "Nutzung: Wöchentlich · alle Modelle: 38%, Sie haben eine Nachricht"] {
            XCTAssertNil(ClaudeDesktopUsageParser.parseUsageButton(other, observedAt: observed), other)
        }
    }

    func testEnglishCardsAndModelSpecificCreditsInDisplayedOrder() throws {
        let report = try XCTUnwrap(parse(["Usage", "Current session", "Resets in 2 hr 15 min", "35% used",
            "Weekly limits", "All models", "Resets Fri 3:00 PM", "72% used",
            "Fable only", "Resets Sun 8:00 AM", "95% used", "Usage credits", "100%"]))
        XCTAssertEqual(report.seen, observed)
        XCTAssertEqual(report.session?.remaining, 65)
        XCTAssertEqual(report.session?.reset, observed.addingTimeInterval(8100))
        XCTAssertEqual(report.session?.resetApproximate, true)
        XCTAssertEqual(report.week?.remaining, 28)
        XCTAssertEqual(report.week?.reset, ISO8601DateFormatter().date(from: "2026-11-27T14:00:00Z"))
        XCTAssertEqual(report.week?.resetPrefix, "Reset")
    }

    func testGermanTextBlocksSplitAXValueAndDuplicateAccessibleLabels() throws {
        let report = try XCTUnwrap(parse(["Aktuelle Sitzung\n85 %\nverbleibend\nWird in 1 Std. 20 Min. zurückgesetzt",
            "85 % verbleibend", "Wöchentliche Limits", "Alle Modelle (inklusive Claude Code)",
            "17", "%", "Zurücksetzung am Fr. um 09:30 Uhr", "Opus", "5%"]))
        XCTAssertEqual(report.session?.remaining, 85)
        XCTAssertEqual(report.session?.reset, observed.addingTimeInterval(4800))
        XCTAssertEqual(report.week?.remaining, 83)
        XCTAssertEqual(report.week?.reset, ISO8601DateFormatter().date(from: "2026-11-27T08:30:00Z"))
        XCTAssertEqual(report.week?.resetLabel, "Zurücksetzung am Fr. um 09:30 Uhr")
    }

    func testSourceSemanticsAndUnlabeledOrExtraContentCannotInventQuotas() throws {
        for rows in [["Chat narrative: 25% used", "10%"], ["Current session", "-3% used"], ["Current session", ".5% used"],
                     ["Current session", "98.7% used", "98.8% used"],
                     ["Weekly limits", "Opus only", "96% used"], ["Current session", "Alarm level", "33%"],
                     ["All models", "67% used"], ["Weekly limits", "25% used", "35% used"],
                     ["Weekly limits", "12% used", "All models", "No data"],
                     ["Current session", "101% used"], ["Current session", "13% of team credits"]] {
            XCTAssertNil(parse(rows), "\(rows)")
        }
        let p = try XCTUnwrap(parse(["Current session: 100% used", "Extra usage", "8% used",
                                    "Weekly limits", "Sonnet", "9% used", "All models · Remaining: 72%"]))
        XCTAssertEqual(p.session?.remaining, 0)
        XCTAssertEqual(p.week?.remaining, 72)
        XCTAssertEqual(parse(["Current session 0% used"])?.session?.remaining, 100)
        XCTAssertEqual(parse(["Current session", "99.9% used", "0.1% left"])?.session?.remaining, 0)
    }

    func testOnlyUnambiguousCardMakesItThrough() throws {
        let report = try XCTUnwrap(parse(["Current session", "15% used", "16% used", "Weekly limits", "All models", "40% used"]))
        XCTAssertNil(report.session)
        XCTAssertEqual(report.week?.remaining, 60)
        let partial = try XCTUnwrap(parse(["Current session", "73% available", "Weekly limits", "Sonnet only", "17% used"]))
        XCTAssertEqual(partial.session?.remaining, 73)
        XCTAssertNil(partial.week)
    }

    func testConflictingResetTimesAreDiscardedAndUnknownZonesNeverGetGuessed() throws {
        let conflicting = try XCTUnwrap(parse(["Current session", "10% used", "Resets in 2h", "Resets in 1h"]))
        XCTAssertEqual(conflicting.session?.remaining, 90)
        XCTAssertNil(conflicting.session?.reset)
        XCTAssertNil(conflicting.session?.resetLabel)
        for label in ["Resets Dec 2 at noon EST", "Resets Fri 3:30 PM UTC−7", "Resets in 2h 15 fortnights",
                      "Resets in 2h and 1h", "Resets in 10 days", "Resets 13:73", "Resets 10:00 PM"] {
            let report = try XCTUnwrap(parse(["Weekly limits", "All models", "1% used", label]))
            XCTAssertNil(report.week?.reset, label)
            XCTAssertEqual(report.week?.resetLabel, label)
        }
        let split = try XCTUnwrap(parse(["Current session", "30%", "Resets in", "2h 5m"]))
        XCTAssertEqual(split.session?.reset, observed.addingTimeInterval(7500))
    }

    func testLocalResetRespectingMidnightAndDaylightSavingTransitions() throws {
        let iso = ISO8601DateFormatter()
        let session = try XCTUnwrap(parse(["Current session", "10% used", "Resets at 07:00"]))
        XCTAssertEqual(session.session?.reset, iso.date(from: "2026-11-25T06:00:00Z"))
        let today = try XCTUnwrap(parse(["Current session", "10% used", "Resets today at 07:00"]))
        XCTAssertNil(today.session?.reset)
        for now in ["2027-03-27T08:00:00Z", "2027-10-30T08:00:00Z"] {
            let report = try XCTUnwrap(parse(["Weekly limits", "30% remaining", "Resets Sunday at 02:30"], at: iso.date(from: now)!))
            XCTAssertNil(report.week?.reset, now)
            XCTAssertEqual(report.week?.resetLabel, "Resets Sunday at 02:30")
        }
    }

    func testLocalizedUsageCardsFromBrowserFixtures() throws {
        // The same visible relative and absolute labels are used by the browser-extension integration tests.
        let examples = [
            ["当前会话", "已使用 ３５％", "将在 2 小时 15 分钟后重置", "每周限额", "所有模型", "剩余 80%", "重置时间：周五 15:30"],
            ["वर्तमान सत्र", "३५% उपयोग किया गया", "२ घंटे १५ मिनट में रीसेट होगा", "साप्ताहिक सीमाएँ", "सभी मॉडल", "८०% शेष", "शुक्रवार को १५:३० बजे रीसेट होगा"],
            ["Sesión actual", "35 % utilizado", "Se restablece en 2 horas y 15 minutos", "Límites semanales", "Todos los modelos", "80 % restante", "Se restablece el viernes a las 15:30"],
            ["الجلسة الحالية", "تم استخدام ٣٥٪؜", "تتم إعادة التعيين بعد ٢ ساعة و١٥ دقيقة", "الحدود الأسبوعية", "جميع النماذج", "٨٠٪ متبقي", "تتم إعادة التعيين يوم الجمعة الساعة ١٥:٣٠"],
            ["Session actuelle", "35 % utilisé", "Réinitialisation dans 2 heures et 15 minutes", "Limites hebdomadaires", "Tous les modèles", "80 % restant", "Réinitialisation le vendredi à 15:30"],
            ["বর্তমান সেশন", "৩৫% ব্যবহৃত", "২ ঘণ্টা ১৫ মিনিট পরে রিসেট হবে", "সাপ্তাহিক সীমা", "সব মডেল", "৮০% বাকি", "শুক্রবার ১৫:৩০ টায় রিসেট হবে"],
            ["Sessão atual", "35 % usado", "Reinicia em 2 horas e 15 minutos", "Limites semanais", "Todos os modelos", "80 % restante", "Reinicia na sexta-feira às 15:30"],
            ["Sesi saat ini", "35% digunakan", "Diatur ulang dalam 2 jam dan 15 menit", "Batas mingguan", "Semua model", "80% tersisa", "Diatur ulang pada Jumat pukul 15:30"],
            ["موجودہ سیشن", "۳۵٪ استعمال ہوا", "۲ گھنٹے ۱۵ منٹ میں ری سیٹ ہوگا", "ہفتہ وار حدود", "تمام ماڈلز", "۸۰٪ باقی", "جمعہ ۱۵:۳۰ بجے ری سیٹ ہوگا"],
        ]
        for row in examples {
            let report = try XCTUnwrap(parse(row), row[0])
            XCTAssertEqual(report.session?.remaining, 65, row[0])
            XCTAssertEqual(report.week?.remaining, 80, row[0])
            XCTAssertEqual(report.session?.resetApproximate, true, row[2])
            XCTAssertEqual(report.session?.reset, observed.addingTimeInterval(8100), row[2])
            XCTAssertEqual(report.week?.reset, ISO8601DateFormatter().date(from: "2026-11-27T14:30:00Z"), row[6])
            XCTAssertEqual(report.week?.resetLabel, row[6])
        }
        XCTAssertEqual(parse(["الجلسة الحالية","٩٩٫٥٪ مستخدم"])?.session?.remaining, 1)
    }
}
