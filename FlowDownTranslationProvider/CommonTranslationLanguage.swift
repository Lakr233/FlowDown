//
//  CommonTranslationLanguage.swift
//  FlowDownTranslationProvider
//
//  Created by GitHub Copilot.
//

import Foundation

enum CommonTranslationLanguage: String, CaseIterable, Identifiable {
    case arabic = "العربية"
    case polish = "Polski"
    case german = "Deutsch"
    case russian = "Русский"
    case french = "Français"
    case korean = "한국어"
    case dutch = "Nederlands"
    case portugueseBrazil = "Português (Brasil)"
    case japanese = "日本語"
    case thai = "ไทย"
    case turkish = "Türkçe"
    case ukrainian = "Українська"
    case spanishSpain = "Español (España)"
    case italian = "Italiano"
    case hindi = "हिन्दी"
    case indonesian = "Bahasa Indonesia"
    case englishUS = "English (US)"
    case englishUK = "English (UK)"
    case vietnamese = "Tiếng Việt"
    case chineseTraditional = "繁體中文"
    case chineseSimplified = "简体中文"

    var id: String {
        rawValue
    }

    var localizedDescription: String {
        let key: String.LocalizationValue = switch self {
        case .arabic: "Arabic"
        case .polish: "Polish"
        case .german: "German"
        case .russian: "Russian"
        case .french: "French"
        case .korean: "Korean"
        case .dutch: "Dutch"
        case .portugueseBrazil: "Portuguese (Brazil)"
        case .japanese: "Japanese"
        case .thai: "Thai"
        case .turkish: "Turkish"
        case .ukrainian: "Ukrainian"
        case .spanishSpain: "Spanish (Spain)"
        case .italian: "Italian"
        case .hindi: "Hindi"
        case .indonesian: "Indonesian"
        case .englishUS: "English (US)"
        case .englishUK: "English (UK)"
        case .vietnamese: "Vietnamese"
        case .chineseTraditional: "Chinese (Mandarin, Traditional)"
        case .chineseSimplified: "Chinese (Mandarin, Simplified)"
        }
        return .init(localized: key)
    }

    var title: String {
        "\(localizedDescription) - \(rawValue)"
    }
}
