@testable import FlowDown
import Testing

struct StorageScopeTests {
    @Test
    func `settings backup errors expose actionable descriptions`() {
        let cases: [SettingsBackupError] = [
            .unsupportedStorage,
            .emptyBackup,
            .invalidBackup,
        ]

        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
