import SwiftUI
import ServiceManagement

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var defaultBrowserID: String {
        didSet {
            UserDefaults.standard.set(defaultBrowserID, forKey: "defaultBrowserID")
        }
    }
    
    @Published var defaultProfileName: String {
        didSet {
            UserDefaults.standard.set(defaultProfileName, forKey: "defaultProfileName")
        }
    }
    
    @Published var profileOrder: [String] {
        didSet {
            UserDefaults.standard.set(profileOrder, forKey: "profileOrder")
        }
    }
    
    init() {
        self.defaultBrowserID = UserDefaults.standard.string(forKey: "defaultBrowserID") ?? KnownBrowser.chrome.id
        self.defaultProfileName = UserDefaults.standard.string(forKey: "defaultProfileName") ?? "Default"
        self.profileOrder = UserDefaults.standard.stringArray(forKey: "profileOrder") ?? []
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var availableProfiles: [BrowserProfile] = []
    
    // カスタムブラウザ管理用
    @State private var customBrowsers: [CustomBrowser] = []
    
    // プロファイル並び替え用
    @State private var allProfilesForOrdering: [BrowserProfile] = []
    
    // ログイン時自動起動管理用 (macOS 13+)
    @State private var isLaunchAtLoginEnabled: Bool = false
    
    var body: some View {
        TabView {
            // MARK: - General Tab
            VStack(alignment: .leading, spacing: 20) {
                Form {
                    Picker("Default Browser", selection: $settings.defaultBrowserID) {
                        // 既知のブラウザ
                        ForEach(KnownBrowser.allCases) { browser in
                            Text(browser.displayName).tag(browser.id)
                        }
                        
                        // カスタムブラウザ
                        if !customBrowsers.isEmpty {
                            Divider()
                            ForEach(customBrowsers, id: \.id) { custom in
                                Text(custom.displayName).tag(custom.id)
                            }
                        }
                    }
                    .onChange(of: settings.defaultBrowserID) { _ in
                        loadProfiles()
                        if let first = availableProfiles.first {
                            settings.defaultProfileName = first.directoryName
                        }
                    }
                    
                    Picker("Default Profile", selection: $settings.defaultProfileName) {
                        if availableProfiles.isEmpty {
                            Text("No Profiles Found").tag("Default")
                        } else {
                            ForEach(availableProfiles, id: \.directoryName) { profile in
                                Text(profile.name).tag(profile.directoryName)
                            }
                        }
                    }
                    
                    if #available(macOS 13.0, *) {
                        Divider()
                        
                        Toggle("Launch at Login", isOn: $isLaunchAtLoginEnabled)
                            .onChange(of: isLaunchAtLoginEnabled) { newValue in
                                toggleLaunchAtLogin(enabled: newValue)
                            }
                    }
                }
                .padding()
                
                Spacer()
                
                HStack {
                    Button("Set as Default Browser") {
                        setAsDefaultBrowser()
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .tabItem { Text("General") }
            
            // MARK: - Custom Browsers Tab
            VStack(alignment: .leading) {
                Text("Add unlisted browsers (.app files) to the selection popup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding([.top, .horizontal])
                
                List {
                    ForEach(customBrowsers, id: \.id) { browser in
                        HStack {
                            Image(nsImage: browser.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(browser.displayName)
                            Spacer()
                            Text(URL(fileURLWithPath: browser.appPath).lastPathComponent)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete(perform: removeCustomBrowser)
                }
                .border(Color.secondary.opacity(0.2))
                .padding(.horizontal)
                
                HStack {
                    Button(action: selectAppAndAdd) {
                        Label("Add Browser...", systemImage: "plus")
                    }
                    
                    Spacer()
                    // 削除用ヒント
                    if !customBrowsers.isEmpty {
                        Text("Select and press Delete key to remove")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .tabItem { Text("Custom Browsers") }
            
            // MARK: - Profile Order Tab
            VStack(alignment: .leading) {
                Text("Drag and drop to reorder profiles in the popup window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding([.top, .horizontal])
                
                List {
                    ForEach(allProfilesForOrdering) { profile in
                        HStack {
                            Image(nsImage: profileIcon(for: profile))
                                .resizable()
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                            Text(profile.name)
                            Spacer()
                            if profile.name != profile.browserName {
                                Text(profile.browserName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onMove(perform: moveProfiles)
                }
                .border(Color.secondary.opacity(0.2))
                .padding(.horizontal)
                .padding(.bottom)
            }
            .tabItem { Text("Ordering") }
        }
        .frame(width: 500, height: 350)
        .padding(.top, 10)
        // 共通の閉じるボタンはウィンドウ枠を使う想定だが、念のため配置
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button("Close") {
                        let localizedTitle = NSLocalizedString("Erabu-kun Settings", comment: "")
                        if let window = NSApplication.shared.windows.first(where: { $0.title == localizedTitle }) {
                            window.close()
                        }
                    }
                    .padding()
                }
            }
        )
        .onAppear {
            self.customBrowsers = ProfileScanner.getCustomBrowsers()
            loadProfiles()
            
            let scanned = ProfileScanner.scanAll()
            let order = settings.profileOrder
            self.allProfilesForOrdering = scanned.sorted { p1, p2 in
                let idx1 = order.firstIndex(of: p1.id) ?? Int.max
                let idx2 = order.firstIndex(of: p2.id) ?? Int.max
                if idx1 == idx2 { return p1.name < p2.name }
                return idx1 < idx2
            }
            
            if #available(macOS 13.0, *) {
                self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
    
    private func loadProfiles() {
        // KnownBrowserかCustomBrowserかを探す
        if let known = KnownBrowser.allCases.first(where: { $0.id == settings.defaultBrowserID }) {
            self.availableProfiles = ProfileScanner.scan(knownBrowser: known)
        } else if let custom = customBrowsers.first(where: { $0.id == settings.defaultBrowserID }) {
            self.availableProfiles = ProfileScanner.scan(customBrowser: custom)
        } else {
            self.availableProfiles = []
        }
    }
    
    private func setAsDefaultBrowser() {
        guard let bundleID = Bundle.main.bundleIdentifier as CFString? else { return }
        
        let httpScheme = "http" as CFString
        let httpsScheme = "https" as CFString
        
        if #available(macOS 12.0, *) {
            LSSetDefaultHandlerForURLScheme(httpScheme, bundleID)
            LSSetDefaultHandlerForURLScheme(httpsScheme, bundleID)
        } else {
            LSSetDefaultHandlerForURLScheme(httpScheme, bundleID)
            LSSetDefaultHandlerForURLScheme(httpsScheme, bundleID)
        }
        print("Set \(bundleID) as default browser.")
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    print("Registered for launch at login")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("Unregistered from launch at login")
                }
            } catch {
                print("Failed to change launch at login status: \(error)")
            }
        }
    }
    
    // MARK: - Custom Browser Actions
    
    private func selectAppAndAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Browser"
        
        if panel.runModal() == .OK, let url = panel.url {
            let appName = (url.lastPathComponent as NSString).deletingPathExtension
            ProfileScanner.addCustomBrowser(name: appName, path: url.path)
            // リストを再読み込み
            self.customBrowsers = ProfileScanner.getCustomBrowsers()
        }
    }
    
    private func removeCustomBrowser(at offsets: IndexSet) {
        for index in offsets {
            let browser = customBrowsers[index]
            ProfileScanner.removeCustomBrowser(id: browser.id)
            
            // もし削除されたブラウザが現在のデフォルトだった場合、Chromeに戻す
            if settings.defaultBrowserID == browser.id {
                settings.defaultBrowserID = KnownBrowser.chrome.id
            }
        }
        self.customBrowsers = ProfileScanner.getCustomBrowsers()
    }
    
    private func moveProfiles(from source: IndexSet, to destination: Int) {
        allProfilesForOrdering.move(fromOffsets: source, toOffset: destination)
        settings.profileOrder = allProfilesForOrdering.map { $0.id }
    }
    
    private func profileIcon(for profile: BrowserProfile) -> NSImage {
        if let path = profile.profileImagePath, let image = NSImage(contentsOfFile: path) {
            return image
        }
        if let path = profile.appPath, !path.isEmpty {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
