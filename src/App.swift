import SwiftUI
import AppKit

@main
struct ErabukunApp: App {
    // AppDelegateを接続（URLのハンドリング等に必要）
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // メニューバーアイコンを動的に取得・リサイズする
    private var menuBarIcon: NSImage {
        if let path = Bundle.main.path(forResource: "bar-icon", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.size = NSSize(width: 18, height: 18)
            // モノクロアイコン（ダーク/ライト対応）として強制認識させる
            image.isTemplate = true
            return image
        }
        // フォールバック用のシステムアイコン
        return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
    }
    
    var body: some Scene {
        // メニューバーに常駐するアイコンとメニュー
        MenuBarExtra {
            Button("Settings...") {
                openSettings()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: menuBarIcon)
        }
    }
    
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        
        let localizedTitle = NSLocalizedString("Erabu-kun Settings", comment: "")
        
        // 既存のウィンドウがあれば最前面に出す
        if let existing = NSApp.windows.first(where: { $0.title == localizedTitle }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        // なければ新しく作成する
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedTitle
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let urlHandler = URLHandler()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSAppleEventManagerにURL処理のイベントを登録
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // 初回起動時のオンボーディング
        if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            openOnboarding()
        }
    }
    
    private func openOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        
        let title = "Erabu-kun へようこそ"
        if let existing = NSApp.windows.first(where: { $0.title == title }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let hostingController = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            // URLHandlerで処理を委譲
            urlHandler.handle(url: url)
        }
    }
}
