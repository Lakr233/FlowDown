@preconcurrency @testable import FlowDown
import Foundation
import Testing
import UIKit

/// The bottom safe area the chat input and the sidebar skip: only an open
/// iPhone Duo in a window wider than tall, with no safe area at the top.
struct UnusedBottomSafeAreaTests {
    #if !targetEnvironment(macCatalyst)
        @Test
        func duoOpenWide_skipsTheWholeBottomSafeArea() {
            let unused = FloatingChrome.unusedBottomSafeArea(
                safeArea: .init(top: 0, left: 0, bottom: 34, right: 62),
                windowSize: .init(width: 951, height: 669),
                idiom: .phone,
            )
            #expect(unused == 34)
        }

        @Test
        func portraitPhone_keepsTheSafeArea() {
            let unused = FloatingChrome.unusedBottomSafeArea(
                safeArea: .init(top: 62, left: 0, bottom: 34, right: 0),
                windowSize: .init(width: 402, height: 874),
                idiom: .phone,
            )
            #expect(unused == 0)
        }

        @Test
        func duoClosed_keepsTheSafeArea() {
            // The status bar is a column at the side here too, but the window
            // is taller than wide.
            let unused = FloatingChrome.unusedBottomSafeArea(
                safeArea: .init(top: 0, left: 0, bottom: 34, right: 48),
                windowSize: .init(width: 466, height: 678),
                idiom: .phone,
            )
            #expect(unused == 0)
        }

        @Test
        func pad_keepsTheSafeArea() {
            for top in [CGFloat(0), 24] {
                let unused = FloatingChrome.unusedBottomSafeArea(
                    safeArea: .init(top: top, left: 0, bottom: 20, right: 0),
                    windowSize: .init(width: 1194, height: 834),
                    idiom: .pad,
                )
                #expect(unused == 0)
            }
        }
    #endif
}
