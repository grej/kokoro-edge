import XCTest
@testable import KokoroEdge

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
}
