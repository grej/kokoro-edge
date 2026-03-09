import XCTest
@testable import KokoroEdge

final class ModelRegistryTests: XCTestCase {
    func testDefaultRegistryContainsKokoro82MWithRequiredFiles() {
        let manifest = ModelRegistry.default.manifest(named: "kokoro-82m")

        XCTAssertNotNil(manifest)
        XCTAssertEqual(
            manifest?.files.map(\.localPath),
            ["kokoro-v1_0.safetensors", "config.json", "voices.npz"]
        )
    }
}
