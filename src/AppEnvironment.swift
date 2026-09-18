import Foundation

/// アプリの実行環境（App Sandbox配下かどうか）を判定するユーティリティ。
///
/// Mac App Store配布版はApp Sandboxが有効(com.apple.security.app-sandbox)だが、
/// Sandbox環境下では `/usr/bin/open --args ...` で他アプリに渡した引数
/// (`--profile-directory=` やコールドスタート時のURLそのもの)がOS側で
/// 握りつぶされてしまい、ブラウザのプロファイル指定機能が実現できない。
/// (App Sandbox自体には無いAppleScript/Local State経由の代替手段も
/// 存在しないことを実機検証済み)
///
/// そのため、配布チャネルによってプロファイル指定機能の有無を自動的に
/// 切り替える。Developer ID配布版（App Sandboxなし）ではフル機能
/// （プロファイル指定込み）、Mac App Store版ではブラウザ選択のみに
/// 縮小して動作する。
enum AppEnvironment {
    /// 現在のプロセスがApp Sandbox配下で動作しているか。
    ///
    /// Sandbox化されたプロセスは `NSHomeDirectory()` が実際のホームディレクトリ
    /// ではなく `~/Library/Containers/<bundle-id>/Data` を返すため、これを
    /// 判定に利用する（Appleの推奨する標準的な検出方法）。
    static var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }
}
