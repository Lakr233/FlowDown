@testable import FlowDown
import Testing
import UIKit

#if !targetEnvironment(macCatalyst) && compiler(>=6.4.2)
    struct SettingControllerVerticalBarTests {
        @Test
        @MainActor
        func settingController_keepsHorizontalBarsForWholeStack() throws {
            guard #available(iOS 27.1, *) else { return }
            let controller = SettingController()
            controller.pushViewController(UIViewController(), animated: false)

            #expect(controller.preferredVerticalBarBehavior == .disabled)
            #expect(controller.childForPreferredVerticalBarBehavior == nil)
        }
    }
#endif
