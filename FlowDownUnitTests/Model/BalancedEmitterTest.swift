@testable import FlowDown
import Foundation
import Testing

private actor ChunkRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func waitForCount(_ expected: Int, timeout: Duration = .seconds(1)) async throws -> [String] {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while values.count < expected, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return values
    }
}

class BalancedEmitterTestSuite {
    @Test
    func `BalancedEmitter batches using size decided at add time`() async throws {
        let recorder = ChunkRecorder()
        let emitter = BalancedEmitter(duration: 0.001, frequency: 2) { chunk in
            Task {
                await recorder.append(chunk)
            }
        }

        await emitter.add("ABCDE")
        await emitter.wait()

        let emitted = try await recorder.waitForCount(2)
        #expect(emitted == ["ABC", "DE"])
        #expect(emitted.joined() == "ABCDE")
    }
}
