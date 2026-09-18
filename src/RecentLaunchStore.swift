import Foundation

/// 直近でリンクを開いた際に使用した「URL + ブラウザ/プロファイル」の組み合わせを
/// メモリ上にのみ保持するストア。
///
/// ディスクへの永続化は行わない（アプリ終了時に破棄される）。
/// メニューバーのメニューから、直近どのプロファイルでリンクを開いたかを
/// 素早く確認できるようにするためのものであり、履歴機能ではない。
struct RecentLaunchEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let browserDisplayName: String
    let profileDisplayName: String
    let date: Date
    /// 再度同じプロファイルで開き直すために保持する（System Defaultフォールバック時はnil）
    let profile: BrowserProfile?

    /// メニュー表示用の短いタイトル（URLのホスト+パスを短縮して表示）
    var shortURLDescription: String {
        guard let host = url.host else { return url.absoluteString }
        let path = url.path
        if path.isEmpty || path == "/" {
            return host
        }
        return "\(host)\(path)"
    }

    /// メニュー表示用のサブタイトル（ブラウザ名 / プロファイル名）
    var browserProfileDescription: String {
        if profileDisplayName.isEmpty || profileDisplayName == browserDisplayName {
            return browserDisplayName
        }
        return "\(browserDisplayName) (\(profileDisplayName))"
    }

    static func == (lhs: RecentLaunchEntry, rhs: RecentLaunchEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class RecentLaunchStore: ObservableObject {
    static let shared = RecentLaunchStore()

    /// 表示する最大件数
    static let maxEntries = 5

    @Published private(set) var entries: [RecentLaunchEntry] = []

    private init() {}

    func record(url: URL, profile: BrowserProfile) {
        record(url: url, browserDisplayName: profile.browserName, profileDisplayName: profile.name, profile: profile)
    }

    func record(url: URL, browserDisplayName: String, profileDisplayName: String, profile: BrowserProfile? = nil) {
        let entry = RecentLaunchEntry(
            url: url,
            browserDisplayName: browserDisplayName,
            profileDisplayName: profileDisplayName,
            date: Date(),
            profile: profile
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
