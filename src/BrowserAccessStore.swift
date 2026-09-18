import Foundation
import AppKit

/// App Sandbox下で、ユーザーが明示的に許可したブラウザのプロファイルデータ
/// フォルダへのアクセス権限を Security-Scoped Bookmark として管理するクラス。
///
/// Chrome系ブラウザのプロファイル情報 (Local State や各プロファイルの
/// アイコン画像) は他アプリのプライベートなデータであり、サンドボックス化
/// されたアプリは自動ではアクセスできない。ユーザーに NSOpenPanel で
/// フォルダを選択してもらい、その結果得られるブックマークを保存することで、
/// 次回以降のアプリ起動時も継続的にアクセスできるようになる。
/// 一度フォルダ単位で許可すれば、以降そのフォルダ内に新しいプロファイルが
/// 追加されても、追加の許可なしに読み取ることができる。
class BrowserAccessStore {
    static let shared = BrowserAccessStore()

    private let keyPrefix = "browserAccessBookmark_"

    private func defaultsKey(for browserId: String) -> String {
        keyPrefix + browserId
    }

    /// 指定ブラウザへのアクセス許可（ブックマーク）が保存されているか
    func hasAccess(for browserId: String) -> Bool {
        UserDefaults.standard.data(forKey: defaultsKey(for: browserId)) != nil
    }

    /// ユーザーにプロファイルデータフォルダの選択を求め、
    /// Security-Scoped Bookmark として保存する。
    @discardableResult
    func requestAccess(for browser: KnownBrowser) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "\(browser.displayName) のプロファイルデータフォルダへのアクセスを許可してください。\n（あらかじめ該当フォルダを開いた状態で表示されます。そのまま「許可」を押してください）"
        panel.prompt = "許可"

        if let suggested = browser.userDataDirectoryURL {
            // 目的のフォルダ自体をブラウズ対象として開く。
            // NSOpenPanel は、フォルダ内で何も選択せず「許可」を押すと
            // 現在開いているフォルダ自体を選択結果として返すため、
            // ユーザーは追加のナビゲーション操作なしにこのフォルダを許可できる。
            //
            // 注意: ここでは FileManager.fileExists による事前確認は行わない。
            // アクセス許可を得る「前」の時点では、サンドボックス化された
            // アプリ自身はこのフォルダの存在確認（stat）すらできないことが多く、
            // fileExists は実在していても false を返してしまう（＝一段上の
            // 階層にフォールバックしてしまい、Edge等で正しいフォルダが
            // 開かれない不具合の原因だった）。
            // NSOpenPanel 自体は Powerbox 経由の別プロセスで動作するため、
            // アプリ側がアクセス権を持たない場所でも問題なくブラウズできる。
            panel.directoryURL = suggested
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: defaultsKey(for: browser.id))
            return true
        } catch {
            print("Failed to create security-scoped bookmark for \(browser.displayName): \(error)")
            return false
        }
    }

    /// 許可を取り消す
    func revokeAccess(for browserId: String) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: browserId))
    }

    /// 保存済みブックマークを解決し、アクセス範囲内でクロージャを実行する。
    /// クロージャの実行が終わるとアクセス権は自動的に解放される。
    func withAccess<T>(for browserId: String, _ body: (URL) -> T) -> T? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: browserId)) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            // ブックマークが古くなっている場合は静かに再生成しておく
            if let refreshed = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: defaultsKey(for: browserId))
            }
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        return body(url)
    }
}
