import Foundation

// SwiftPM генерирует Bundle.module для executable-таргета; в Xcode-таргете ресурсы лежат в main bundle.
extension Bundle {
    static let module = Bundle.main
}
