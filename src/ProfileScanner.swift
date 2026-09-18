import Foundation
import AppKit

class ProfileScanner {
    
    // カスタムブラウザの保存キー
    private static let customBrowsersKey = "customBrowsers"

    /// App Store用スクリーンショット撮影時に、実際のブラウザ/プロファイル情報の
    /// 代わりにダミーデータを表示するためのデモモード。
    /// `ERABUKUN_SCREENSHOT_DEMO=1` 環境変数を付けて起動した場合のみ有効になり、
    /// 通常の配布ビルド・通常起動には一切影響しない。
    private static var isScreenshotDemoMode: Bool {
        ProcessInfo.processInfo.environment["ERABUKUN_SCREENSHOT_DEMO"] == "1"
    }

    private static func demoProfiles() -> [BrowserProfile] {
        [
            BrowserProfile(
                browserId: KnownBrowser.chrome.id,
                browserName: KnownBrowser.chrome.displayName,
                directoryName: "Default",
                name: "Work",
                isProfileSupported: true,
                appPath: nil
            ),
            BrowserProfile(
                browserId: KnownBrowser.chrome.id,
                browserName: KnownBrowser.chrome.displayName,
                directoryName: "Profile 1",
                name: "Personal",
                isProfileSupported: true,
                appPath: nil
            ),
            BrowserProfile(
                browserId: KnownBrowser.edge.id,
                browserName: KnownBrowser.edge.displayName,
                directoryName: "Default",
                name: "Work",
                isProfileSupported: true,
                appPath: nil
            )
        ]
    }

    /// インストール済みの全ブラウザのプロファイルをスキャンする
    static func scanAll() -> [BrowserProfile] {
        if isScreenshotDemoMode {
            return demoProfiles()
        }

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
        if isScreenshotDemoMode {
            return demoProfiles().filter { $0.browserId == knownBrowser.id }
        }

        let fileManager = FileManager.default
        
        // インストールチェック (Application フォルダ等に存在するか)
        guard let bundleId = knownBrowser.bundleIdentifier,
              let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              fileManager.fileExists(atPath: appUrl.path) else {
            return [] // アプリが存在しない
        }
        
        // プロファイルをサポートしないブラウザ（Safari, Firefox等）の場合は、単体プロファイルとして返す。
        // また、App Sandbox配下（Mac App Store版）ではプロファイル指定機能自体が
        // 実現できないため、プロファイル対応ブラウザであっても単体プロファイル
        // として扱い、ブラウザ単位の選択のみを提供する。
        if !knownBrowser.supportsProfiles || AppEnvironment.isSandboxed {
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
        
        // Chrome系のプロファイルサポートブラウザの場合、ユーザーが許可した
        // フォルダ (Security-Scoped Bookmark) 経由でのみ Local State を読み取れる。
        // 未許可の場合は、設定画面でアクセスを許可してもらうまで表示できない。
        guard BrowserAccessStore.shared.hasAccess(for: knownBrowser.id) else {
            return []
        }
        
        let profiles = BrowserAccessStore.shared.withAccess(for: knownBrowser.id) { userDataDirURL in
            scanProfiles(userDataDirURL: userDataDirURL, knownBrowser: knownBrowser, appUrl: appUrl)
        }
        
        return profiles ?? []
    }
    
    /// アクセス許可済みのユーザーデータフォルダから Local State を読み取り、プロファイル一覧を構築する。
    /// 呼び出し元で Security-Scoped Resource へのアクセスが開始されている前提。
    private static func scanProfiles(userDataDirURL: URL, knownBrowser: KnownBrowser, appUrl: URL) -> [BrowserProfile] {
        let fileManager = FileManager.default
        let localStateURL = userDataDirURL.appendingPathComponent("Local State")
        
        // Local State ファイルがない（起動したことがないなど）場合でも、デフォルトプロファイルとして１つ返す
        guard fileManager.fileExists(atPath: localStateURL.path) else {
            let defaultImageData = findProfileImageData(userDataDirURL: userDataDirURL, directoryName: "Default", knownBrowser: knownBrowser)
            return [
                BrowserProfile(
                    browserId: knownBrowser.id,
                    browserName: knownBrowser.displayName,
                    directoryName: "Default",
                    name: "Default",
                    isProfileSupported: true,
                    appPath: appUrl.path,
                    profileImageData: defaultImageData
                )
            ]
        }
        
        var profiles: [BrowserProfile] = []
        
        do {
            let data = try Data(contentsOf: localStateURL)
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let profileNode = json["profile"] as? [String: Any],
               let infoCache = profileNode["info_cache"] as? [String: [String: Any]] {
                
                for (directoryName, cacheData) in infoCache {
                    let displayName = cacheData["name"] as? String ?? directoryName
                    let imageData = findProfileImageData(userDataDirURL: userDataDirURL, directoryName: directoryName, knownBrowser: knownBrowser)
                    
                    let profile = BrowserProfile(
                        browserId: knownBrowser.id,
                        browserName: knownBrowser.displayName,
                        directoryName: directoryName,
                        name: displayName,
                        isProfileSupported: true,
                        appPath: appUrl.path,
                        profileImageData: imageData
                    )
                    profiles.append(profile)
                }
            }
        } catch {
            print("Failed to read Local State for \(knownBrowser.displayName): \(error)")
        }
        
        // プロファイルが見つからなかった場合のフォールバック
        if profiles.isEmpty {
            let defaultImageData = findProfileImageData(userDataDirURL: userDataDirURL, directoryName: "Default", knownBrowser: knownBrowser)
            profiles.append(
                BrowserProfile(
                    browserId: knownBrowser.id,
                    browserName: knownBrowser.displayName,
                    directoryName: "Default",
                    name: "Default",
                    isProfileSupported: true,
                    appPath: appUrl.path,
                    profileImageData: defaultImageData
                )
            )
        }
        
        return profiles.sorted { $0.name < $1.name }
    }
    
    /// インストール済みだが、まだフォルダアクセスが許可されていないプロファイル対応ブラウザか判定する。
    /// 設定画面で「アクセスを許可」の導線を出すために使用する。
    static func needsAccessGrant(for knownBrowser: KnownBrowser) -> Bool {
        guard knownBrowser.supportsProfiles,
              let bundleId = knownBrowser.bundleIdentifier,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            return false
        }
        return !BrowserAccessStore.shared.hasAccess(for: knownBrowser.id)
    }
    
    private static func findProfileImageData(userDataDirURL: URL, directoryName: String, knownBrowser: KnownBrowser) -> Data? {
        let profileDirURL = userDataDirURL.appendingPathComponent(directoryName)
        let fileManager = FileManager.default
        for picName in knownBrowser.profilePictureFileNames {
            let picURL = profileDirURL.appendingPathComponent(picName)
            if fileManager.fileExists(atPath: picURL.path) {
                return try? Data(contentsOf: picURL)
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
