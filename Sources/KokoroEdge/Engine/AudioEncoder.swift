import Foundation

struct AudioEncoder {
    static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let pcmSamples: [Int16] = samples.map { sample in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16((clamped * 32767.0).rounded())
        }

        let pcmDataSize = pcmSamples.count * MemoryLayout<Int16>.size
        let riffChunkSize = 36 + pcmDataSize
        let byteRate = sampleRate * MemoryLayout<Int16>.size
        let blockAlign = UInt16(MemoryLayout<Int16>.size)
        let bitsPerSample = UInt16(16)

        var data = Data()
        data.reserveCapacity(44 + pcmDataSize)

        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: UInt32(riffChunkSize).littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: UInt32(byteRate).littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: UInt32(pcmDataSize).littleEndianBytes)

        for sample in pcmSamples {
            data.append(contentsOf: sample.littleEndianBytes)
        }

        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
