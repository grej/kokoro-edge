import XCTest
@testable import KokoroEdge

private let failingPassagePart1 =
    "At the end of January, the US department of justice released its biggest drop yet of documents related to Jeffrey Epstein, the convicted paedophile and erstwhile friend of Trump who died in prison."

private let failingPassagePart2 =
    "Lurid headlines based on the documents followed, about foreign women allegedly buried on Epstein's New Mexico ranch, about Epstein's purchase of 330 gallons of sulphuric acid, and a woman who claimed Trump raped her when she was aged 13. The Wall Street Journal reported the government took 47,635 files offline “for further review”."

private let failingCombinedPassage = "\(failingPassagePart1) \(failingPassagePart2)"

final class TextPreprocessorTests: XCTestCase {
    func testNormalizeReplacesSmartPunctuationAndWhitespace() {
        let input = "“Hello”—world…\u{00A0}It’s fine.\n\n\nNext\tline."
        let normalized = TextPreprocessor.normalize(input)

        XCTAssertEqual(normalized, "\"Hello\"--world... It's fine.\n\nNext line.")
    }

    func testChunkPrefersSentenceBoundariesUnderHardLimit() {
        let sentence = "This is a sentence with enough words to matter but it should still stay intact."
        let input = Array(repeating: sentence, count: 12).joined(separator: " ")
        let chunks = TextPreprocessor.chunk(input, targetTokens: 25, maxTokens: 40)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { TextPreprocessor.estimatedTokenCount($0) <= 40 })
        XCTAssertTrue(chunks.allSatisfy { $0.last == "." })
    }

    func testChunkSplitsOversizedSentenceByClausesOrWords() {
        let phrase = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
        let input = Array(repeating: phrase, count: 20).joined(separator: " ")
        let chunks = TextPreprocessor.chunk(input, targetTokens: 20, maxTokens: 30)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { TextPreprocessor.estimatedTokenCount($0) <= 30 })
    }

    func testPrepareReturnsNormalizedTextAndChunks() {
        let prepared = TextPreprocessor.prepare("It’s a test…")

        XCTAssertEqual(prepared.normalizedText, "It's a test...")
        XCTAssertEqual(prepared.chunks, ["It's a test..."])
    }

    func testRefineSplitsTextIntoSmallerChunks() {
        let sentence = Array(repeating: "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu", count: 12)
            .joined(separator: " ")

        let refined = TextPreprocessor.refine(sentence)

        XCTAssertGreaterThan(refined.count, 1)
        XCTAssertTrue(refined.allSatisfy { !$0.isEmpty })
    }

    func testPrepareNormalizesCombinedFailingPassageAndKeepsItAsSingleChunk() {
        let prepared = TextPreprocessor.prepare(failingCombinedPassage)

        XCTAssertEqual(
            prepared.normalizedText,
            "\(failingPassagePart1) Lurid headlines based on the documents followed, about foreign women allegedly buried on Epstein's New Mexico ranch, about Epstein's purchase of 330 gallons of sulphuric acid, and a woman who claimed Trump raped her when she was aged 13. The Wall Street Journal reported the government took 47,635 files offline \"for further review\"."
        )
        XCTAssertEqual(prepared.chunks, [prepared.normalizedText])
    }
}
