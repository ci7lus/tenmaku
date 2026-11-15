import Foundation

enum LocalizationResources {
    static func require(in bundle: Bundle = .main) {
        let requiredFiles = [
            "ja.lproj/Localizable.strings",
            "en.lproj/Localizable.strings",
            "en.lproj/Localizable.stringsdict",
        ]
        for path in requiredFiles {
            let url = bundle.resourceURL?.appendingPathComponent(path)
            let values = try? url?.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
            guard values?.isRegularFile == true, values?.isReadable == true else {
                NSLog("Tenmaku: Required localization resource unavailable: %@. Launch the packaged Tenmaku.app.", path)
                exit(EXIT_FAILURE)
            }
        }
    }
}
