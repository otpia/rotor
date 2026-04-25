import CoreText
import Foundation

enum FontRegistrar {
    private static let bundled = [
        "CourierPrime-Regular",
        "CourierPrime-Bold",
    ]

    // 在 App 启动时调用一次；重复注册会返回 kCTFontManagerErrorAlreadyRegistered，忽略即可
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
