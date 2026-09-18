import SwiftUI
import AppKit

class URLHandler {
    
    private var windowControllers: [NSWindowController] = []
    
    /// システムから渡されたURLを処理する
    func handle(url: URL) {
        // 設定画面用や別のカスタムスキーマでないか確認 (http/httpsのみ処理)
        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            return
        }
        
        showPopup(for: url)
    }
    
    private func showPopup(for url: URL) {
        // 既存のポップアップがあれば閉じる
        closeAllPopups()
        
        var isResolved = false
        
        let cancelAction = { [weak self] in
            guard !isResolved else { return }
            isResolved = true
            BrowserLauncher.launchWithDefaultSettings(url: url)
            self?.closeAllPopups()
        }
        
        let popupView = PopupView(
            url: url,
            onSelect: { [weak self] profile in
                guard !isResolved else { return }
                isResolved = true
                BrowserLauncher.launch(url: url, profile: profile)
                self?.closeAllPopups()
            },
            onCancel: cancelAction
        )
        
        // SwiftUI ViewをNSHostingControllerにラップ
        let hostingController = NSHostingController(rootView: popupView)
        
        // 最前面の一時的なパネルとしてWindowを構築
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .popUpMenu
        window.hidesOnDeactivate = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController
        
        // マウスカーソルの位置付近に表示
        if let screen = NSScreen.main {
            let mouseLocation = NSEvent.mouseLocation
            // 少し上にずらしてポップアップ表示
            let popupOrigin = NSPoint(x: mouseLocation.x - 200, y: mouseLocation.y + 20)
            window.setFrameOrigin(popupOrigin)
            
            // 画面外にはみ出ないように補正
            if !screen.frame.contains(window.frame) {
                window.center()
            }
        } else {
            window.center()
        }
        
        let windowController = PopupTargetWindowController(window: window, onCancel: cancelAction)
        
        windowControllers.append(windowController)
        
        // アクティブにして最前面に出す
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    func closeAllPopups() {
        for controller in windowControllers {
            controller.window?.close()
        }
        windowControllers.removeAll()
    }
}

/// ウィンドウ外のクリック（Deactivate）やEsc/Enterキーを監視するためのカスタムWindowController
class PopupTargetWindowController: NSWindowController, NSWindowDelegate {
    var onCancel: (() -> Void)?
    
    init(window: NSWindow?, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(window: window)
        window?.delegate = self
        
        // EscやEnterキーの監視用（ローカルイベントモニター）
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc = 53, Enter = 36
            if event.keyCode == 53 || event.keyCode == 36 {
                self.onCancel?()
                return nil
            }
            return event
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // ウィンドウがフォーカスを失った（外側がクリックされた等）場合にキャンセル処理を実行
    func windowDidResignKey(_ notification: Notification) {
        onCancel?()
    }
}
