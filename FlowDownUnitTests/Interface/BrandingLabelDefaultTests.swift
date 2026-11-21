@testable import FlowDown
import Foundation
import Testing

struct BrandingLabelDefaultTests {
    @Test
    func `default branding follows the localized display name`() {
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: ["CFBundleDisplayName": "浮望"]) == "浮望")
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: ["CFBundleDisplayName": "FlowDown"]) == "FlowDown")
    }

    @Test
    func `default branding falls back to FlowDown without a display name`() {
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: nil) == "FlowDown")
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: [:]) == "FlowDown")
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: ["CFBundleDisplayName": ""]) == "FlowDown")
    }

    @Test(arguments: [("zh-Hans", "浮望"), ("zh-Hant", "浮望"), ("en", "FlowDown")])
    func `app bundle ships the localized display name`(localization: String, expected: String) throws {
        let path = try #require(Bundle(for: BrandingLabel.self).path(
            forResource: "InfoPlist",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: localization,
        ))
        let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: Any])
        #expect(BrandingLabel.defaultBrandingValue(localizedInfoDictionary: strings) == expected)
    }
}
