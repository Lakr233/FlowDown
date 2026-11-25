@testable import FlowDown
import Testing
import UIKit

struct SettingFooterViewTests {
    @Test
    @MainActor
    func versionLabel_longPressOpensWelcome() throws {
        let footer = SettingController.SettingContent.SettingFooterView()
        let label = footer.versionLabel

        #expect(label.isUserInteractionEnabled)
        #expect(label.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } == true)

        var opened = 0
        footer.onShowWelcome = { opened += 1 }
        let action = try #require(label.accessibilityCustomActions?.first)
        #expect(action.name == String(localized: "Show Welcome Screen"))
        #expect(action.actionHandler?(action) == true)
        #expect(opened == 1)
    }
}
