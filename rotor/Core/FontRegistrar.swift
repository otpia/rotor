import CoreText
import Foundation

enum FontRegistrar {
    private static let bundled = [
        "CourierPrime-Regular",
        "CourierPrime-Bold",
    ]

    // Call once at app launch; duplicate registration returns kCTFontManagerErrorAlreadyRegistered, which can be ignored
    static func registerBundledFonts() {
        for name in bundled {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[FontRegistrar] 缺失字体文件：\(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                if let cfError = error?.takeRetainedValue() {
                    let code = CFErrorGetCode(cfError)
                    // 105 = kCTFontManagerErrorAlreadyRegistered
                    if code != 105 {
                        print("[FontRegistrar] 注册 \(name) 失败：\(cfError)")
                    }
                }
            }
        }
    }
}
