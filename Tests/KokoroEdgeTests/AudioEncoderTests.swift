import Foundation
import XCTest
@testable import KokoroEdge

final class AudioEncoderTests: XCTestCase {
    func testEncodeWAVProducesRIFFHeader() {
        let wavData = AudioEncoder.encodeWAV(samples: [0.0, 0.5, -0.5], sampleRate: 24_000)

        XCTAssertEqual(String(decoding: wavData.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wavData[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wavData[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: wavData[36..<40], as: UTF8.self), "data")
    }

    func testEncodeWAVWritesExpectedSizes() {
        let samples: [Float] = [0.0, 0.25, -0.25, 1.0]
        let wavData = AudioEncoder.encodeWAV(samples: samples, sampleRate: 24_000)

        XCTAssertEqual(wavData.count, 44 + (samples.count * 2))
        XCTAssertEqual(readUInt32LE(from: wavData, offset: 4), UInt32(36 + (samples.count * 2)))
        XCTAssertEqual(readUInt32LE(from: wavData, offset: 40), UInt32(samples.count * 2))
    }

    func testEncodeWAVWritesSampleRate() {
        let wavData = AudioEncoder.encodeWAV(samples: [0.0, 0.1], sampleRate: 24_000)

        XCTAssertEqual(readUInt32LE(from: wavData, offset: 24), 24_000)
        XCTAssertEqual(readUInt32LE(from: wavData, offset: 28), 48_000)
    }

    private func readUInt32LE(from data: Data, offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) { partialResult, item in
            partialResult | (UInt32(item.element) << (item.offset * 8))
        }
    }
}
