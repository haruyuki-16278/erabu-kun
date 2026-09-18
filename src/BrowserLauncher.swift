import Foundation
import AppKit

class BrowserLauncher {
    
    /// BrowserProfileオブジェクトからURLを開く
    static func launch(url: URL, profile: BrowserProfile) {
        let targetAppPath = profile.appPath ?? "/Applications/\(profile.browserName).app"

        // NOTE: App Sandbox環境下では、`/usr/bin/open --args ...` で渡した引数が
        // 起動先アプリ（Chrome/Edge等）に一切伝わらないことが実機検証で判明した。
        // (NSWorkspace.openApplication(configuration.arguments) も同様に伝わらない。
        // Local State書き換えやAppleScript経由のプロファイル指定も存在しないことを
        // 実機検証済み)
        // 一方で `--args` を使わず URL を通常の「開く対象」としてそのまま渡す
        // (`open -n -a <app> <url>`) 場合は、Sandbox下でも正常にURLが渡って開かれる。
        //
        // そのため、Sandbox配下（Mac App Store版）では `--profile-directory=` の
        // 付与を諦めてURLのみを渡し（＝ブラウザ選択のみ）、Sandboxなし
        // （Developer ID配布版）では従来通りプロファイル指定込みで起動する。
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if AppEnvironment.isSandboxed {
            task.arguments = ["-n", "-a", targetAppPath, url.absoluteString]
        } else {
            var arguments = ["-n", "-a", targetAppPath, "--args"]
            if profile.isProfileSupported {
                arguments.append("--profile-directory=\(profile.directoryName)")
            }
            arguments.append(url.absoluteString)
            task.arguments = arguments
        }

        do {
            try task.run()
            // メニューバーの「最近開いたリンク」表示用に記録（永続化はしない）
            DispatchQueue.main.async {
                RecentLaunchStore.shared.record(url: url, profile: profile)
            }
        } catch {
            print("Failed to launch browser: \(error)")
        }
    }
    
    /// デフォルト設定で開く（SettingsViewで保存された値を使用）
    static func launchWithDefaultSettings(url: URL) {
        let settings = AppSettings.shared
        let allProfiles = ProfileScanner.scanAll()
        
        // 保存されているデフォルトブラウザIDとプロファイル名に合致するものを探す
        if let targetProfile = allProfiles.first(where: {
            $0.browserId == settings.defaultBrowserID && $0.directoryName == settings.defaultProfileName
        }) {
            launch(url: url, profile: targetProfile)
        } else {
            // 見つからなければOSのデフォルトで開く（フォールバック）
            NSWorkspace.shared.open(url)
            DispatchQueue.main.async {
                RecentLaunchStore.shared.record(
                    url: url,
                    browserDisplayName: "System Default",
                    profileDisplayName: ""
                )
            }
        }
    }
}
