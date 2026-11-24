import Foundation

/// Parses the ordered accessibility labels of the Claude Desktop usage pane. No UI or network dependencies.
enum ClaudeDesktopUsageParser {
    private enum Card { case session, weekly, allModels }
    private struct Reading {
        var values: Set<Decimal> = []
        var resetLabels: [String] = []
        var invalid = false
    }

    // Usage card vocabulary shared with BrowserExtension/signals.js (German, English and nine other UI languages).
    private static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0 == "|" || $0.isNewline }).map { key(String($0)) })
    }
    private static let session = words("""
        current session|aktuelle sitzung|laufende sitzung|5-hour session|5 hour session|5-hour limit|5 hour limit|5-stunden-limit|5 stunden limit
        当前会话|本次会话|当前工作阶段
        वर्तमान सत्र|मौजूदा सत्र
        Sesión actual
        الجلسة الحالية|الجلسة الجارية
        Session actuelle|Session en cours
        বর্তমান সেশন|চলতি সেশন
        Sessão atual
        Sesi saat ini|Sesi berjalan
        موجودہ سیشن
        """)
    private static let weekly = words("""
        this week|weekly|diese woche|wöchentlich|cette semaine|hebdomadaire|esta semana|本周|इस हफ़्ते|هذا الأسبوع|এই সপ্তাহ|minggu ini|اس ہفتے
        weekly limits|weekly limit|weekly usage|wöchentliches limit|wöchentliche limits|wöchentliche nutzung|wochenlimit|wochenlimits
        每周限额|每周使用量|每周限制|每周用量
        साप्ताहिक सीमाएँ|साप्ताहिक सीमा|साप्ताहिक उपयोग
        Límites semanales|Límite semanal|Uso semanal
        الحدود الأسبوعية|حدود الاستخدام الأسبوعية|الاستخدام الأسبوعي|الحد الأسبوعي
        Limites hebdomadaires|Limite hebdomadaire|Utilisation hebdomadaire
        সাপ্তাহিক সীমা|সাপ্তাহিক ব্যবহারের সীমা|সাপ্তাহিক ব্যবহার
        Limites semanais|Limite semanal|Uso semanal|Utilização semanal
        Batas mingguan|Batas penggunaan mingguan|Penggunaan mingguan
        ہفتہ وار حدود|ہفتہ وار حد|ہفتہ وار استعمال
        """)
    private static let all = words("""
        all models|alle modelle
        所有模型|全部模型
        सभी मॉडल
        Todos los modelos
        جميع النماذج|كل النماذج
        Tous les modèles
        সব মডেল|সমস্ত মডেল|সকল মডেল
        Todos os modelos
        Semua model
        تمام ماڈلز|تمام ماڈل
        """)
    private static let other = words("""
        usage by product|usage breakdown|nutzung nach produkt|nutzung nach produkten|utilisation par produit|uso por producto|uso por produto
        extra usage|additional usage|usage credits|limit resets|limit reset|zusätzliche nutzung|zusatznutzung|nutzungsguthaben|nutzungscredits|limit zurücksetzen
        额外用量|额外使用量|使用额度
        अतिरिक्त उपयोग|उपयोग क्रेडिट
        Uso adicional|Créditos de uso
        الاستخدام الإضافي|أرصدة الاستخدام
        Utilisation supplémentaire|Crédits d’utilisation
        অতিরিক্ত ব্যবহার|ব্যবহারের ক্রেডিট
        Uso adicional|Uso extra|Utilização adicional|Créditos de uso
        Penggunaan tambahan|Kredit penggunaan
        اضافی استعمال|استعمال کے کریڈٹس
        """)
    private static let used = words("""
        used|consumed|utilized|utilised|verbraucht|genutzt|verwendet|ausgeschöpft|belegt
        已使用|已用|已消耗
        उपयोग किया गया|उपयोग हो चुका है|इस्तेमाल किया गया|उपयोग हुआ
        utilizado|utilizada|utilizados|usado|usada|consumido|de uso
        مستخدم|مُستخدم|مستهلك|تم استخدام|تم استخدامه|تم استهلاك
        utilisé|utilisés|utilisée|consommé|consommée
        ব্যবহৃত|ব্যবহার করা হয়েছে|ব্যবহার হয়েছে|ব্যবহৃত হয়েছে
        utilizado|utilizada|usado|usada|consumido|de uso
        digunakan|terpakai
        استعمال ہوا|استعمال شدہ|استعمال کیا گیا|استعمال ہو چکا ہے
        """)
    private static let left = words("""
        remaining|left|available|übrig|verbleibend|verfügbar|frei
        剩余|可用
        शेष|शेष है|उपलब्ध|बाकी
        restante|disponible
        متبقٍ|متبقي|المتبقي|متاحة|متاح
        restant|restante|restants|disponible
        অবশিষ্ট|বাকি|উপলভ্য
        restante|disponível
        tersisa|tersedia
        باقی|باقی ہے|دستیاب
        """)

    private static let sectionEnd = try! NSRegularExpression(pattern:
        #"(?i)(?:^|[^\p{L}])(?:opus|sonnet|haiku|fable)(?:$|[^\p{L}])|^(?:extra usage|usage credits|additional usage|zusätzliche nutzung|zusatznutzung|credits?\b|billing\b|monthly\b|monatslimit\b)"#)
    private static let quantity = try! NSRegularExpression(pattern: #"^([^%\d]*?)([0-9]{1,3}(?:[.,][0-9]+)?)\s*%\s*([^%\d]*)$"#)
    private static let plainNumber = try! NSRegularExpression(pattern: #"^[0-9]{1,3}(?:[.,][0-9]+)?$"#)
    private static let joinedHeading = try! NSRegularExpression(pattern: #"^(.+?)\s+(?=[0-9]{1,3}(?:[.,][0-9]+)?\s*%)"#)

    // Only the reader may select this path, after identifying the official usage-meter AXButton.
    // Its closed label's bare percentage is *used*, confirmed against the same meter in the open panel.
    private static let buttonPrefix = words("nutzung|usage")
    private static let buttonKind = words("wöchentlich · alle modelle|weekly · all models|5-stunden-limit|5-hour limit|5-hour session")
    private static let buttonPayload = try! NSRegularExpression(pattern:
        #"^([0-9]{1,3}(?:[.,][0-9]+)?\s*%)(?:\s*,\s*(.+))?$"#)

    static func parseUsageButton(_ label: String, observedAt: Date, timeZone: TimeZone = .current) -> LimitReport? {
        guard label.count <= 240, !label.contains(where: \.isNewline) else { return nil }
        let parts = clean(label).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, buttonPrefix.contains(key(parts[0])), buttonKind.contains(key(parts[1])) else { return nil }
        let payload = clean(parts[2])
        guard let match = captures(buttonPayload, payload), percentage(key(match[1])) != nil else { return nil }
        var lines = [parts[1], match[1]]
        if !match[2].isEmpty {
            guard !match[2].contains("%"), resetBody(key(match[2])) != nil else { return nil }
            lines.append(match[2])
        }
        return parse(lines, observedAt: observedAt, timeZone: timeZone)
    }

    static func parse(_ lines: [String], observedAt: Date, timeZone: TimeZone = .current) -> LimitReport? {
        guard lines.count <= 1024, lines.allSatisfy({ $0.utf8.count <= 32_768 }),
              lines.reduce(0, { $0 + $1.utf8.count }) <= 131_072 else { return nil }
        var active: Card?
        var weeklySection = false
        var sawAllModels = false
        var groups: [Card: Reading] = [:]
        let rows = preparedRows(lines)
        var i = 0
        while i < rows.count {
            let raw = rows[i]
            i += 1
            let name = key(raw)
            if session.contains(name) {
                active = .session
                weeklySection = false
            } else if weekly.contains(name) {
                active = .weekly
                weeklySection = true
            } else if isAll(name) {
                active = weeklySection ? .allModels : active == .session ? .session : nil
                sawAllModels = sawAllModels || weeklySection
            } else if other.contains(name) || matches(sectionEnd, name) {
                active = nil
                // A later "All models" can follow an individual model in the weekly section.
                if other.contains(name) { weeklySection = false }
            } else if let card = active {
                var valueLine = name
                if matches(plainNumber, name), i < rows.count, key(rows[i]) == "%" {
                    valueLine += "%"
                    i += 1
                }
                if used.contains(name) || left.contains(name) {
                    if i < rows.count, barePercentage(key(rows[i])) {
                        valueLine += " " + key(rows[i])
                        i += 1
                    }
                } else if barePercentage(valueLine), i < rows.count {
                    let qualifier = key(rows[i])
                    if used.contains(qualifier) || left.contains(qualifier) {
                        valueLine += " " + qualifier
                        i += 1
                    }
                }
                if valueLine.contains("%") {
                    if let remaining = percentage(valueLine) {
                        groups[card, default: Reading()].values.insert(remaining)
                    } else {
                        groups[card, default: Reading()].invalid = true
                    }
                } else if let reset = resetBody(name) {
                    var label = raw
                    // Electron can expose "Resets in" and "2 hr 4 min" as neighboring static text nodes.
                    if reset.body.isEmpty, i < rows.count {
                        let next = key(rows[i])
                        if next.first?.isNumber == true, !next.contains("%"), rows[i].count <= 75 {
                            label += " " + rows[i]
                            i += 1
                        }
                    }
                    if label.count <= 100, !groups[card, default: Reading()].resetLabels.contains(label) {
                        groups[card, default: Reading()].resetLabels.append(label)
                    }
                } else {
                    // End a card on an unknown heading so its percentage cannot be borrowed from another meter.
                    active = nil
                }
            }
        }

        let current = window(groups[.session], weekly: false, observedAt: observedAt, timeZone: timeZone)
        let week = window(groups[sawAllModels ? .allModels : .weekly], weekly: true, observedAt: observedAt, timeZone: timeZone)
        guard current != nil || week != nil else { return nil }
        return LimitReport(seen: observedAt, session: current, week: week)
    }

    private static func window(_ reading: Reading?, weekly: Bool, observedAt: Date, timeZone: TimeZone) -> LimitWindow? {
        guard let reading, !reading.invalid, reading.values.count == 1, let value = reading.values.first else { return nil }
        var result = LimitWindow(remaining: NSDecimalNumber(decimal: value).doubleValue.rounded(), reset: nil)
        guard let first = reading.resetLabels.first, let parsed = resetBody(key(first)) else { return result }
        let date = resolve(parsed, weekly: weekly, now: observedAt, timeZone: timeZone)
        // Repeated AX labels are common. Conflicting reset observations are unusable, even with an agreed percent.
        for label in reading.resetLabels.dropFirst() {
            guard let other = resetBody(key(label)), let actual = date,
                  resolve(other, weekly: weekly, now: observedAt, timeZone: timeZone) == actual else { return result }
        }
        result.resetLabel = first
        result.reset = date
        if date != nil { result.resetApproximate = parsed.relative }
        return result
    }

    private static func clean(_ string: String) -> String {
        let remove = CharacterSet(charactersIn: "\u{061c}\u{200e}\u{200f}\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2066}\u{2067}\u{2068}\u{2069}")
        return string.unicodeScalars.filter { !remove.contains($0) }.map(String.init).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func key(_ string: String) -> String {
        let normalized = clean(string.precomposedStringWithCompatibilityMapping)
            .lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "٪", with: "%")
            .replacingOccurrences(of: "٫", with: ".")
        var value = normalized.unicodeScalars.map { char -> String in
            if char.properties.numericType == .decimal, let n = char.properties.numericValue { return String(Int(n)) }
            return String(char)
        }.joined()
        while let last = value.last, ".:。!?؟। ".contains(last) { value.removeLast() }
        return value
    }

    private static func isAll(_ name: String) -> Bool {
        all.contains(name) || (name.hasSuffix(")") && name.firstIndex(of: "(").map {
            all.contains(name[..<$0].trimmingCharacters(in: .whitespaces))
        } == true)
    }

    private static func heading(_ name: String) -> Bool {
        session.contains(name) || weekly.contains(name) || isAll(name) || other.contains(name)
    }

    private static func preparedRows(_ source: [String]) -> [String] {
        var result: [String] = []
        for blob in source {
            for fragment in blob.split(whereSeparator: \.isNewline) {
                let raw = clean(String(fragment))
                guard !raw.isEmpty else { continue }
                for part in raw.components(separatedBy: " · ") {
                    let name = key(part)
                    if let colon = part.firstIndex(where: { $0 == ":" || $0 == "：" }),
                       heading(key(String(part[..<colon]))) {
                        result.append(String(part[..<colon]))
                        let tail = clean(String(part[part.index(after: colon)...]))
                        if !tail.isEmpty { result.append(tail) }
                    } else if let m = captures(joinedHeading, name), heading(m[1]) {
                        result.append(m[1])
                        result.append(String(name.dropFirst(m[0].count)))
                    } else {
                        result.append(part)
                    }
                }
            }
        }
        return result
    }

    private static func barePercentage(_ name: String) -> Bool {
        guard let parts = captures(quantity, name) else { return false }
        return parts[1].isEmpty && parts[3].isEmpty
    }

    private static func percentage(_ name: String) -> Decimal? {
        guard let parts = captures(quantity, name), let value = Decimal(string: parts[2].replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              (0...100).contains(value) else { return nil }
        let before = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        let after = parts[3].trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard before.isEmpty || after.isEmpty else { return nil }
        let qualifier = before.isEmpty ? after : before
        if qualifier.isEmpty || used.contains(qualifier) { return 100 - value }
        return left.contains(qualifier) ? value : nil
    }

    private struct Reset {
        let body: String
        let relative: Bool
    }

    private static func regexes(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.map { try! NSRegularExpression(pattern: $0) }
    }

    private static let relative = regexes([
        #"^(?:resets?|resetting|wird|zurücksetzung|zurücksetzen|zurückgesetzt|nächste zurücksetzung)\s*:?\s+(?:in|nach)\b\s*(.*?)(?:\s+zurückgesetzt)?$"#,
        #"^(?:将在|将于|在)?\s*(.+?)\s*(?:后重置|后重设)$"#, #"^(?:重置倒计时|距离重置还有)\s*[:：]?\s*(.*)$"#,
        #"^(.+?)\s+(?:में|के बाद)\s+रीसेट (?:होगा|होगी|होता है)$"#,
        #"^(?:se (?:restablece|restablecerá|reinicia|reiniciará)|restablecimiento|reinicio)\s+(?:dentro de|en)\s+(.*)$"#,
        #"^(?:(?:تتم|ستتم|يتم) )?(?:إعادة التعيين|إعادة الضبط|إعادة التعيين التالية)\s+(?:بعد|خلال)\s+(.*)$"#,
        #"^(?:réinitialisation|réinitialisée?|se réinitialise|sera réinitialisée?)\s+dans\s+(.*)$"#,
        #"^(.+?)\s+(?:পরে|পর)\s+রিসেট (?:হবে|হয়)$"#,
        #"^(?:redefine|redefinição|reinicia|reinicializa|será (?:redefinid[oa]|reiniciad[oa]))\s+(?:em|dentro de)\s+(.*)$"#,
        #"^(?:direset|diatur ulang|akan (?:direset|diatur ulang))\s+dalam\s+(.*)$"#,
        #"^(.+?)\s+(?:میں|کے بعد)\s+ری سیٹ (?:ہو گا|ہو گی|ہوگا|ہوگی|ہوتا ہے)$"#
    ])
    private static let absolute = regexes([
        #"^(?:resets?|resetting|zurücksetzung|zurücksetzen|nächste zurücksetzung)(?:\b|$)\s*:?\s*(.*)$"#,
        #"^wird\s+(.+?)\s+zurückgesetzt$"#,
        #"^(?:重置时间|下次重置|将于|于)\s*[:：]?\s*(.+?)(?:重置)?$"#,
        #"^(.+?)\s+रीसेट (?:होगा|होगी|होता है)$"#,
        #"^(?:se (?:restablece|restablecerá|reinicia|reiniciará)|restablecimiento|reinicio)\s*:?\s+(.+)$"#,
        #"^(?:(?:تتم|ستتم|يتم) )?(?:إعادة التعيين|إعادة الضبط)\s*:?\s+(.+)$"#,
        #"^(?:réinitialisation|réinitialisée?|se réinitialise|sera réinitialisée?)\s*:?\s+(.+)$"#,
        #"^(.+?)\s+রিসেট (?:হবে|হয়)$"#,
        #"^(?:redefine|redefinição|reinicia|reinicializa|será (?:redefinid[oa]|reiniciad[oa]))\s*:?\s+(.+)$"#,
        #"^(?:direset|diatur ulang|akan (?:direset|diatur ulang))\s*:?\s+(.+)$"#,
        #"^(.+?)\s+ری سیٹ (?:ہو گا|ہو گی|ہوگا|ہوگی|ہوتا ہے)$"#
    ])

    private static func resetBody(_ line: String) -> Reset? {
        for regex in relative {
            if let match = captures(regex, line) { return Reset(body: match[1], relative: true) }
        }
        for regex in absolute {
            if let match = captures(regex, line) { return Reset(body: match[1], relative: false) }
        }
        return nil
    }

    private static let units: [String: Int] = {
        let groups = [
            (86400, "days|day|tagen|tage|tag|d|jours|jour|días|día|dias|dia|hari|天|日|दिन|أيام|يوم|দিন|دن"),
            (3600, "hours|hour|hrs|hr|stunden|stunde|std|h|heures|heure|horas|hora|jam|小时|小時|घंटे|घंटों|घंटा|ساعات|ساعة|ঘণ্টা|ঘন্টা|گھنٹے|گھنٹہ"),
            (60, "minutes|minute|minuten|minutos|minuto|mins|min|m|menit|分钟|分|मिनट|دقائق|دقيقة|মিনিট|منٹ"),
            (1, "seconds|second|sekunden|sekunde|sek|secs|sec|s|secondes|seconde|segundos|segundo|detik|秒钟|秒|सेकंड|ثوانٍ|ثوان|ثانية|সেকেন্ড|سیکنڈ")]
        var result: [String: Int] = [:]
        for (period, labels) in groups {
            for label in words(labels) { result[label] = period }
        }
        return result
    }()
    private static let part = try! NSRegularExpression(pattern: #"^([0-9]{1,4})\s*("#
        + units.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")\.?"#)
    private static let conjunction = try! NSRegularExpression(pattern: #"^(?:[,،、]\s*)?(?:(?:and|und|et|y|e|dan|और|এবং|اور)\s+|و\s*)?"#)

    private static func duration(_ input: String) -> TimeInterval? {
        var suffix = input.trimmingCharacters(in: .whitespaces)
        var total = 0
        var seen = Set<Int>()
        while !suffix.isEmpty {
            guard let m = captures(part, suffix), let n = Int(m[1]), let unit = units[m[2]], seen.insert(unit).inserted else { return nil }
            total += n * unit
            suffix = String(suffix.dropFirst(m[0].count)).trimmingCharacters(in: .whitespaces)
            if !suffix.isEmpty, let glue = captures(conjunction, suffix), !glue[0].isEmpty {
                suffix = String(suffix.dropFirst(glue[0].count)).trimmingCharacters(in: .whitespaces)
                if suffix.isEmpty { return nil }
            }
        }
        return !seen.isEmpty && total <= 8 * 86_400 ? Double(total) : nil
    }

    private static let clock = try! NSRegularExpression(pattern:
        #"^(.*?)([0-9]{1,2})(?:(?::|\s*h\s*)([0-9]{2}))?\s*(am|pm|a\.m|p\.m|uhr|ص|م)?$"#)
    private static let dayStart = try! NSRegularExpression(pattern: #"^(?:on|am|le|el|em|no|na|pada|يوم|在)\s*\b\s*"#)
    private static let clockWord = try! NSRegularExpression(pattern: #"(?:^|\s)(?:at|um|à|a las|às|pukul|الساعة|को|في)$"#)
    private static let clockEnd = try! NSRegularExpression(pattern: #"\s*(?:बजे|টায়|بجے)$"#)
    private static let today = words("today|heute|今天|आज|hoy|اليوم|aujourd'hui|আজ|hoje|hari ini|آج")
    private static let tomorrow = words("tomorrow|morgen|明天|कल|mañana|غدًا|غدا|demain|আগামীকাল|amanhã|besok|کل")
    private static let weekdays: [String: Int] = {
        var days: [String: Int] = ["tues": 3, "thurs": 5, "周日": 1, "周一": 2, "周二": 3, "周三": 4, "周四": 5, "周五": 6, "周六": 7]
        for locale in ["en", "de", "fr", "es", "pt", "id", "hi", "ar", "bn", "ur", "zh_Hans"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: locale)
            f.calendar = Calendar(identifier: .gregorian)
            for labels in [f.weekdaySymbols, f.shortWeekdaySymbols, f.standaloneWeekdaySymbols, f.shortStandaloneWeekdaySymbols] {
                for (index, label) in (labels ?? []).enumerated() { days[key(label)] = index + 1 }
            }
        }
        return days
    }()

    private static func resolve(_ reset: Reset, weekly: Bool, now: Date, timeZone: TimeZone) -> Date? {
        if reset.relative { return duration(reset.body).map { now.addingTimeInterval($0) } }
        let body = replace(clockEnd, in: reset.body, with: "")
        guard let m = captures(clock, body), var hour = Int(m[2]), hour <= 23 else { return nil }
        let minute = Int(m[3]) ?? 0
        guard minute < 60, !m[3].isEmpty || !m[4].isEmpty else { return nil }
        if !m[4].isEmpty && m[4] != "uhr" {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (["pm", "p.m", "م"].contains(m[4]) ? 12 : 0)
        }
        var day = m[1].trimmingCharacters(in: .whitespaces)
        day = replace(dayStart, in: day, with: "")
        day = replace(clockWord, in: day, with: "")
        day = key(day.trimmingCharacters(in: CharacterSet(charactersIn: " ,،，·")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let offset: Int
        if let index = weekdays[day] { offset = (index - calendar.component(.weekday, from: now) + 7) % 7 }
        else if today.contains(day) || (day.isEmpty && !weekly) { offset = 0 }
        else if tomorrow.contains(day) { offset = 1 }
        else { return nil }
        func at(_ days: Int) -> Date? {
            guard let target = calendar.date(byAdding: .day, value: days, to: start),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: target,
                                           matchingPolicy: .strict, repeatedTimePolicy: .first),
                  calendar.isDate(date, inSameDayAs: target) else { return nil }
            // A repeated civil time has two possible instants on the autumn DST change.
            let later = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: target,
                                      matchingPolicy: .strict, repeatedTimePolicy: .last)
            return date == later ? date : nil
        }
        guard let date = at(offset) else { return nil }
        if date >= now { return date }
        if weekdays[day] != nil { return at(offset + 7) }
        return day.isEmpty ? at(1) : nil
    }

    private static func captures(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool { captures(regex, text) != nil }
    private static func replace(_ regex: NSRegularExpression, in value: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement)
    }
}
