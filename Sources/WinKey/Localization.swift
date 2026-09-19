import Foundation

/// 本地化取词。
///
/// 优先在自己 bundle 的对应 lproj 里查找；找不到时回退到 key 本身，
/// 这样漏翻的条目在界面上会显示成 key（能被一眼发现），而不是空白。
func L(_ key: String, _ comment: String = "") -> String {
    let value = NSLocalizedString(key, bundle: .main, comment: comment)
    return value
}
