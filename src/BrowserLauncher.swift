import Foundation
import AppKit

class BrowserLauncher {
    
    /// BrowserProfileオブジェクトからURLを開く
    static func launch(url: URL, profile: BrowserProfile) {
        let task = Process()
        
        // BundleIdentifier や Path からアプリケーションを指定
        let targetAppPath = profile.appPath ?? "/Applications/\(profile.browserName).app"
        
        if profile.isProfileSupported && profile.directoryName != "Default" {
            // Chromium系でプロファイルを使う場合は `open` 経由ではなく、
            // 直接内部の実行ファイル (MacOS/Google Chrome など) を叩く方が引数が安定して渡る。
            // bundle identifier などを元に実行ファイルパスを特定する簡易的な方法。
            let executableName = URL(fileURLWithPath: targetAppPath).deletingPathExtension().lastPathComponent
            let binPath = "\(targetAppPath)/Contents/MacOS/\(executableName)"
            
            if FileManager.default.fileExists(atPath: binPath) {
                // 直接実行ファイルを実行
                task.executableURL = URL(fileURLWithPath: binPath)
                task.arguments = [
                    "--profile-directory=\(profile.directoryName)",
                    url.absoluteString
                ]
            } else {
                // 安全策として open コマンドに渡す場合
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [
                    "-n", "-a", targetAppPath,
                    "--args", "--profile-directory=\(profile.directoryName)", url.absoluteString
                ]
            }
        } else {
            // プロファイル指定がない場合は標準の open コマンド
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", "-a", targetAppPath, url.absoluteString]
        }
        
        do {
            try task.run()
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
        }
    }
}
