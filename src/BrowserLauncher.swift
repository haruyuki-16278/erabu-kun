import Foundation
import AppKit

class BrowserLauncher {
    
    /// BrowserProfileオブジェクトからURLを開く
    static func launch(url: URL, profile: BrowserProfile) {
        let targetAppPath = profile.appPath ?? "/Applications/\(profile.browserName).app"
        let appURL = URL(fileURLWithPath: targetAppPath)
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        // LaunchServices (NSWorkspace) 経由で起動する。実行ファイルを直接 Process() で
        // execするのと異なり、App Sandbox環境でも特別なentitlementなしに動作する。
        var arguments: [String] = []
        if profile.isProfileSupported && profile.directoryName != "Default" {
            arguments.append("--profile-directory=\(profile.directoryName)")
        }
        arguments.append(url.absoluteString)
        configuration.arguments = arguments
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error = error {
                print("Failed to launch browser: \(error)")
            }
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
        }
    }
}
