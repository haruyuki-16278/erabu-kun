import Foundation
import AppKit

class ProfileScanner {
    
    // カスタムブラウザの保存キー
    private static let customBrowsersKey = "customBrowsers"
    
    /// インストール済みの全ブラウザのプロファイルをスキャンする
    static func scanAll() -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []
        
        // 1. 既知のブラウザのスキャン
        for browser in KnownBrowser.allCases {
            profiles.append(contentsOf: scan(knownBrowser: browser))
        }
        
        // 2. ユーザーが追加したカスタムブラウザのスキャン
        for customBrowser in getCustomBrowsers() {
            profiles.append(contentsOf: scan(customBrowser: customBrowser))
        }
        
        return profiles
    }
    
    /// 既知のブラウザのプロファイルをスキャン
    static func scan(knownBrowser: KnownBrowser) -> [BrowserProfile] {
        let fileManager = FileManager.default
        
        // インストールチェック (Application フォルダ等に存在するか)
        guard let bundleId = knownBrowser.bundleIdentifier,
              let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              fileManager.fileExists(atPath: appUrl.path) else {
            return [] // アプリが存在しない
        }
        
        // プロファイルをサポートしないブラウザ（Safari, Firefox等）の場合は、単体プロファイルとして返す
        if !knownBrowser.supportsProfiles {
            return [
                BrowserProfile(
                    browserId: knownBrowser.id,
                    browserName: knownBrowser.displayName,
                    directoryName: "Default",
                    name: knownBrowser.displayName,
                    isProfileSupported: false,
                    appPath: appUrl.path
                )
            ]
        }
        
        // Chrome系のプロファイルサポートブラウザの場合、Local State をスキャンする
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        guard let relativePath = knownBrowser.localStateRelativePath else { return [] }
        
        let localStateURL = appSupportURL.appendingPathComponent(relativePath)
        
        // Local State ファイルがない（起動したことがないなど）場合でも、デフォルトプロファイルとして１つ返す
        guard fileManager.fileExists(atPath: localStateURL.path) else {
            let defaultImagePath = findProfileImagePath(userDataDirURL: localStateURL.deletingLastPathComponent(), directoryName: "Default", knownBrowser: knownBrowser)
            return [
                BrowserProfile(
                    browserId: knownBrowser.id,
                    browserName: knownBrowser.displayName,
                    directoryName: "Default",
                    name: "Default",
                    isProfileSupported: true,
                    appPath: appUrl.path,
                    profileImagePath: defaultImagePath
                )
            ]
        }
        
        var profiles: [BrowserProfile] = []
        
        do {
            let data = try Data(contentsOf: localStateURL)
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let profileNode = json["profile"] as? [String: Any],
               let infoCache = profileNode["info_cache"] as? [String: [String: Any]] {
                
                let userDataDirURL = localStateURL.deletingLastPathComponent()
                
                for (directoryName, cacheData) in infoCache {
                    let displayName = cacheData["name"] as? String ?? directoryName
                    let imagePath = findProfileImagePath(userDataDirURL: userDataDirURL, directoryName: directoryName, knownBrowser: knownBrowser)
                    
                    let profile = BrowserProfile(
                        browserId: knownBrowser.id,
                        browserName: knownBrowser.displayName,
                        directoryName: directoryName,
                        name: displayName,
                        isProfileSupported: true,
                        appPath: appUrl.path,
                        profileImagePath: imagePath
                    )
                    profiles.append(profile)
                }
            }
        } catch {
            print("Failed to read Local State for \(knownBrowser.displayName): \(error)")
        }
        
        // プロファイルが見つからなかった場合のフォールバック
        if profiles.isEmpty {
            let defaultImagePath = findProfileImagePath(userDataDirURL: localStateURL.deletingLastPathComponent(), directoryName: "Default", knownBrowser: knownBrowser)
            profiles.append(
                BrowserProfile(
                    browserId: knownBrowser.id,
                    browserName: knownBrowser.displayName,
                    directoryName: "Default",
                    name: "Default",
                    isProfileSupported: true,
                    appPath: appUrl.path,
                    profileImagePath: defaultImagePath
                )
            )
        }
        
        return profiles.sorted { $0.name < $1.name }
    }
    
    private static func findProfileImagePath(userDataDirURL: URL, directoryName: String, knownBrowser: KnownBrowser) -> String? {
        let profileDirURL = userDataDirURL.appendingPathComponent(directoryName)
        let fileManager = FileManager.default
        for picName in knownBrowser.profilePictureFileNames {
            let picURL = profileDirURL.appendingPathComponent(picName)
            if fileManager.fileExists(atPath: picURL.path) {
                return picURL.path
            }
        }
        return nil
    }
    
    /// カスタムブラウザのスキャン（プロファイル機能は持たない前提で1つのアプリとして返す）
    static func scan(customBrowser: CustomBrowser) -> [BrowserProfile] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: customBrowser.appPath) {
            return [
                BrowserProfile(
                    browserId: customBrowser.id,
                    browserName: customBrowser.displayName,
                    directoryName: "Default",
                    name: customBrowser.displayName,
                    isProfileSupported: false,
                    appPath: customBrowser.appPath
                )
            ]
        }
        return []
    }
    
    // MARK: - カスタムブラウザの管理機能
    
    static func getCustomBrowsers() -> [CustomBrowser] {
        guard let data = UserDefaults.standard.data(forKey: customBrowsersKey),
              let browsers = try? JSONDecoder().decode([CustomBrowser].self, from: data) else {
            return []
        }
        return browsers
    }
    
    static func addCustomBrowser(name: String, path: String) {
        var browsers = getCustomBrowsers()
        let newBrowser = CustomBrowser(id: UUID().uuidString, displayName: name, appPath: path)
        browsers.append(newBrowser)
        
        if let encoded = try? JSONEncoder().encode(browsers) {
            UserDefaults.standard.set(encoded, forKey: customBrowsersKey)
        }
    }
    
    static func removeCustomBrowser(id: String) {
        var browsers = getCustomBrowsers()
        browsers.removeAll { $0.id == id }
        
        if let encoded = try? JSONEncoder().encode(browsers) {
            UserDefaults.standard.set(encoded, forKey: customBrowsersKey)
        }
    }
}
