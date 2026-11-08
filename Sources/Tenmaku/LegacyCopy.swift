import Foundation

enum LegacyCopy {
    private static let usesJapanese = Bundle.preferredLocalizations(from: ["en", "ja"]).first == "ja"

    static func text(_ english: String, _ japanese: String) -> String {
        usesJapanese ? japanese : english
    }
}
