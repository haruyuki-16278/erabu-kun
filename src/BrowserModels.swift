import Foundation
import AppKit

/// ブラウザの基本情報を表現するプロトコル
protocol BrowserRepresentable: Identifiable, Hashable {
    var id: String { get }
    var displayName: String { get }
    var bundleIdentifier: String? { get }
    var icon: NSImage { get }
}

/// インストール済みの既知のブラウザの種類
enum KnownBrowser: String, CaseIterable, BrowserRepresentable {
    case chrome = "Google Chrome"
    case chromeBeta = "Google Chrome Beta"
    case chromeCanary = "Google Chrome Canary"
    case edge = "Microsoft Edge"
    case edgeBeta = "Microsoft Edge Beta"
    case edgeDev = "Microsoft Edge Dev"
    case edgeCanary = "Microsoft Edge Canary"
    case brave = "Brave Browser"
    case vivaldi = "Vivaldi"
    case opera = "Opera"
    case arc = "Arc"
    case safari = "Safari"
    case firefox = "Firefox"
    case firefoxDeveloperEdition = "Firefox Developer Edition"
    
    var id: String { self.rawValue }
    var displayName: String { self.rawValue }
    
    var bundleIdentifier: String? {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .chromeBeta: return "com.google.Chrome.beta"
        case .chromeCanary: return "com.google.Chrome.canary"
        case .edge: return "com.microsoft.edgemac"
        case .edgeBeta: return "com.microsoft.edgemac.Beta"
        case .edgeDev: return "com.microsoft.edgemac.Dev"
        case .edgeCanary: return "com.microsoft.edgemac.Canary"
        case .brave: return "com.brave.Browser"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .opera: return "com.operasoftware.Opera"
        case .arc: return "company.thebrowser.Browser"
        case .safari: return "com.apple.Safari"
        case .firefox: return "org.mozilla.firefox"
        case .firefoxDeveloperEdition: return "org.mozilla.firefoxdeveloperedition"
        }
    }
    
    var icon: NSImage {
        if let bundleId = bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
    
    // プロファイルを管理するディレクトリ構成を持つブラウザか（Chromeベースのもの）
    var supportsProfiles: Bool {
        switch self {
        case .chrome, .chromeBeta, .chromeCanary,
             .edge, .edgeBeta, .edgeDev, .edgeCanary,
             .brave, .vivaldi:
            return true
        default:
            return false
        }
    }
    
    // プロファイル画像の候補ファイル名
    var profilePictureFileNames: [String] {
        switch self {
        case .chrome, .chromeBeta, .chromeCanary:
            return ["Google Profile Picture.png", "Profile Picture.png"]
        case .edge, .edgeBeta, .edgeDev, .edgeCanary:
            return ["Edge Profile Picture.png", "Profile Picture.png"]
        case .brave:
            return ["Brave Profile Picture.png", "Profile Picture.png"]
        case .vivaldi:
            return ["Vivaldi Profile Picture.png", "Profile Picture.png"]
        default:
            return ["Profile Picture.png"]
        }
    }
    
    // Local State の保存場所パス（Application Support以下）
    var localStateRelativePath: String? {
        switch self {
        case .chrome: return "Google/Chrome/Local State"
        case .chromeBeta: return "Google/Chrome Beta/Local State"
        case .chromeCanary: return "Google/Chrome Canary/Local State"
        case .edge: return "Microsoft Edge/Local State"
        case .edgeBeta: return "Microsoft Edge Beta/Local State"
        case .edgeDev: return "Microsoft Edge Dev/Local State"
        case .edgeCanary: return "Microsoft Edge Canary/Local State"
        case .brave: return "BraveSoftware/Brave-Browser/Local State"
        case .vivaldi: return "Vivaldi/Local State"
        default: return nil
        }
    }
    
    // プロファイルデータ (Local State や各プロファイルフォルダ) が置かれているディレクトリ。
    // App Sandbox 環境では、このフォルダをユーザーに選択してもらいアクセス許可を得る必要がある。
    var userDataDirectoryURL: URL? {
        guard let relativePath = localStateRelativePath else { return nil }
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent(relativePath).deletingLastPathComponent()
    }
}

/// ユーザーが独自に追加したブラウザを表現する構造体
struct CustomBrowser: BrowserRepresentable, Codable {
    let id: String         // UUIDなどを文字列で
    let displayName: String
    let appPath: String    // アプリのフルパス
    
    var bundleIdentifier: String? {
        Bundle(path: appPath)?.bundleIdentifier
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: appPath)
    }
}

/// BrowserProfile: 抽出された個別のプロファイル（単体ブラウザ含む）を表す
struct BrowserProfile: Identifiable, Hashable {
    var id: String { "\(browserId)_\(directoryName)" }
    let browserId: String         // KnownBrowser.id または CustomBrowser.id
    let browserName: String
    let directoryName: String     // ディレクトリ名 または "Default"
    let name: String              // 表示名
    let isProfileSupported: Bool  // プロファイル引数(--profile-directory)を使うか
    let appPath: String?          // カスタムブラウザ用の起動パス
    // プロファイル画像。App Sandbox下ではフォルダへのアクセス権がスキャン後に
    // 失効するため、パスではなくスキャン時に読み込んだ画像データを保持する。
    var profileImageData: Data? = nil
}

