import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var selectedTab = 0
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                // Step 1: Welcome
                VStack(spacing: 20) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .frame(width: 80, height: 80)
                    
                    Text("Erabu-kun へようこそ")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Erabu-kun は、クリックしたリンクを最適なブラウザで開くためのルーターアプリです。")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .padding(.top, 40)
                .tag(0)
                
                // Step 2: Behavior (Popup & Default)
                VStack(spacing: 20) {
                    Image(systemName: "cursorarrow.click.2")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.blue)
                    
                    Text("リンクを開くときの動作")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            Image(systemName: "1.circle.fill").foregroundColor(.accentColor)
                            Text("リンクをクリックすると、画面中央にブラウザ選択ダイアログが表示され、選んだブラウザ・プロファイルで開かれます。")
                        }
                        
                        HStack(alignment: .top) {
                            Image(systemName: "2.circle.fill").foregroundColor(.accentColor)
                            Text("ダイアログ外をクリック（またはEscキーを押す）と、設定してある「デフォルトブラウザ」で開かれます。")
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .padding(.top, 40)
                .tag(1)
                
                // Step 3: Default Browser Setup
                VStack(spacing: 20) {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.green)
                    
                    Text("デフォルトブラウザに設定")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("リンクを Erabu-kun で受け取るためには、macOS のデフォルトブラウザに設定する必要があります。")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: {
                        setAsDefaultBrowser()
                    }) {
                        Text("デフォルトブラウザに設定する")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 60)
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .padding(.top, 40)
                .tag(2)
                
                // Step 4: Menu bar access
                VStack(spacing: 20) {
                    Image(systemName: "menubar.rectangle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.primary)
                    
                    Text("設定へのアクセス")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("Erabu-kun はメニューバー（画面右上）に常駐しています。")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("アイコンをクリックし「Settings...」を選ぶと、いつでもデフォルトブラウザやプロファイルの並び順を変更できます。まずはそのまま使ってみましょう！")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    Button("使い始める！") {
                        hasSeenOnboarding = true
                        closeWindow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 20)
                }
                .padding(.top, 40)
                .tag(3)
            }
            
            // Navigation controls
            HStack {
                if selectedTab > 0 {
                    Button("戻る") {
                        withAnimation { selectedTab -= 1 }
                    }
                }
                Spacer()
                if selectedTab < 3 {
                    Button("次へ") {
                        withAnimation { selectedTab += 1 }
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
    
    private func setAsDefaultBrowser() {
        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"

        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error = error {
                    print("Onboarding: Failed to set default handler for \(scheme): \(error)")
                }
            }
        }
        print("Onboarding: Set \(bundleID) as default browser.")
        
        // Show a brief alert to confirm
        let alert = NSAlert()
        alert.messageText = "設定完了"
        alert.informativeText = "デフォルトブラウザの変更をOSにリクエストしました。ダイアログが表示された場合は「Erabu-kun」への変更を許可してください。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func closeWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Erabu-kun へようこそ" }) {
            window.close()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
