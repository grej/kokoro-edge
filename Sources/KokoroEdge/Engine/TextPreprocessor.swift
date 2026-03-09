import Foundation
import NaturalLanguage

struct PreparedText: Equatable, Sendable {
    let normalizedText: String
    let chunks: [String]
}

enum TextPreprocessor {
    static let defaultTargetTokens = 175
    static let defaultMaxTokens = 250

    static func prepare(
        _ text: String,
        targetTokens: Int = defaultTargetTokens,
        maxTokens: Int = defaultMaxTokens
    ) -> PreparedText {
        let normalized = normalize(text)
        let chunks = chunk(normalized, targetTokens: targetTokens, maxTokens: maxTokens)
        return PreparedText(normalizedText: normalized, chunks: chunks)
    }

    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var normalized = text.precomposedStringWithCompatibilityMapping

        let replacements: [(String, String)] = [
            ("\u{00A0}", " "),
            ("\u{2007}", " "),
            ("\u{202F}", " "),
            ("\u{2018}", "'"),
            ("\u{2019}", "'"),
            ("\u{201A}", "'"),
            ("\u{201B}", "'"),
            ("\u{201C}", "\""),
            ("\u{201D}", "\""),
            ("\u{201E}", "\""),
            ("\u{201F}", "\""),
            ("\u{2032}", "'"),
            ("\u{2033}", "\""),
            ("\u{2013}", "-"),
            ("\u{2014}", "--"),
            ("\u{2015}", "--"),
            ("\u{2212}", "-"),
            ("\u{2026}", "..."),
            ("\u{00B7}", "*"),
            ("\u{2022}", "*"),
            ("\u{00AD}", ""),
            ("\u{FEFF}", ""),
        ]

        for (source, replacement) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: replacement)
        }

        normalized = normalized.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)

        let sanitizedScalars = normalized.unicodeScalars.map { scalar -> String in
            if scalar.isASCII {
                return String(scalar)
            }

            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return String(scalar)
            }

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return scalar == "\n" ? "\n" : " "
            }

            if CharacterSet.punctuationCharacters.contains(scalar) {
                return " "
            }

            if CharacterSet.symbols.contains(scalar) {
                return " "
            }

            return ""
        }.joined()

        var cleaned = sanitizedScalars.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chunk(
        _ text: String,
        targetTokens: Int = defaultTargetTokens,
        maxTokens: Int = defaultMaxTokens
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let units = paragraphs.flatMap { paragraph in
            splitOversizedUnits(sentenceUnits(in: paragraph), maxTokens: maxTokens)
        }

        guard !units.isEmpty else { return [trimmed] }

        var chunks: [String] = []
        var currentUnits: [String] = []
        var currentTokenCount = 0

        func flush() {
            guard !currentUnits.isEmpty else { return }
            chunks.append(currentUnits.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines))
            currentUnits.removeAll(keepingCapacity: true)
            currentTokenCount = 0
        }

        for unit in units {
            let tokenCount = estimatedTokenCount(unit)

            if currentUnits.isEmpty {
                currentUnits = [unit]
                currentTokenCount = tokenCount
                continue
            }

            if currentTokenCount >= targetTokens || currentTokenCount + tokenCount > maxTokens {
                flush()
            }

            currentUnits.append(unit)
            currentTokenCount += tokenCount
        }

        flush()

        return chunks.isEmpty ? [trimmed] : chunks
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        let pattern = #"[A-Za-z0-9]+|[^\sA-Za-z0-9]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.numberOfMatches(in: text, range: range) ?? max(1, text.split(separator: " ").count)
    }

    static func refine(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let refined = chunk(trimmed, targetTokens: 90, maxTokens: 140)
        if refined.count > 1 {
            return refined
        }

        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > 1 else {
            let midpoint = trimmed.index(trimmed.startIndex, offsetBy: max(1, trimmed.count / 2))
            let left = String(trimmed[..<midpoint]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(trimmed[midpoint...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return [left, right].filter { !$0.isEmpty }
        }

        let midpoint = words.count / 2
        let left = words[..<midpoint].joined(separator: " ")
        let right = words[midpoint...].joined(separator: " ")
        return [left, right].filter { !$0.isEmpty }
    }

    private static func sentenceUnits(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        if sentences.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        return sentences
    }

    private static func splitOversizedUnits(_ units: [String], maxTokens: Int) -> [String] {
        units.flatMap { unit in
            if estimatedTokenCount(unit) <= maxTokens {
                return [unit]
            }

            let clauses = splitByRegex(unit, pattern: #"(?<=[,;:])\s+"#)
            if clauses.count > 1 {
                return clauses.flatMap { splitOversizedUnits([$0], maxTokens: maxTokens) }
            }

            return splitByWords(unit, maxTokens: maxTokens)
        }
    }

    private static func splitByRegex(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return [text] }

        var pieces: [String] = []
        var lastIndex = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let piece = text[lastIndex..<matchRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                pieces.append(String(piece))
            }
            lastIndex = matchRange.upperBound
        }

        let tail = text[lastIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            pieces.append(String(tail))
        }

        return pieces.isEmpty ? [text] : pieces
    }

    private static func splitByWords(_ text: String, maxTokens: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return [text] }

        var chunks: [String] = []
        var currentWords: [Substring] = []
        var currentTokens = 0

        for word in words {
            let tokenCount = estimatedTokenCount(String(word))
            if !currentWords.isEmpty && currentTokens + tokenCount > maxTokens {
                chunks.append(currentWords.joined(separator: " "))
                currentWords.removeAll(keepingCapacity: true)
                currentTokens = 0
            }
            currentWords.append(word)
            currentTokens += tokenCount
        }

        if !currentWords.isEmpty {
            chunks.append(currentWords.joined(separator: " "))
        }

        return chunks
    }
}
