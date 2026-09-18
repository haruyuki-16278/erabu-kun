import SwiftUI

struct PopupView: View {
    let url: URL
    let onSelect: (BrowserProfile) -> Void
    let onCancel: () -> Void
    
    @State private var profiles: [BrowserProfile] = []
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Choose a browser to open the link")
                .font(.headline)
                .padding(.top, 4)
            
            Text(url.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal)
            
            Divider()
                .padding(.bottom, 8)
            
            if profiles.isEmpty {
                Text("Loading profiles...")
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(profiles) { profile in
                            ProfileCardView(profile: profile)
                                .onTapGesture {
                                    onSelect(profile)
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: 600, minHeight: 400, maxHeight: 600)
        // ESCキーや外側クリックのキャンセルは Window 側でハンドリングする
        .onAppear {
            let scanned = ProfileScanner.scanAll()
            let order = AppSettings.shared.profileOrder
            self.profiles = scanned.sorted { p1, p2 in
                let idx1 = order.firstIndex(of: p1.id) ?? Int.max
                let idx2 = order.firstIndex(of: p2.id) ?? Int.max
                if idx1 == idx2 { return p1.name < p2.name }
                return idx1 < idx2
            }
        }
    }
}

struct ProfileCardView: View {
    let profile: BrowserProfile
    @State private var isHovered = false
    
    var profileImage: NSImage? {
        if let path = profile.profileImagePath, let image = NSImage(contentsOfFile: path) {
            return image
        }
        return nil
    }
    
    // ブラウザ・プロファイルに応じたアイコンを取得
    var browserIcon: NSImage {
        if let path = profile.appPath, !path.isEmpty {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let profileImage = profileImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    
                    Image(nsImage: browserIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(Circle())
                        .offset(x: 4, y: 4)
                } else {
                    Image(nsImage: browserIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
            .frame(width: 68, height: 68)
            
            VStack(spacing: 2) {
                Text(profile.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if profile.name != profile.browserName {
                    Text(profile.browserName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .foregroundColor(.clear)
                }
            }
            .frame(height: 36) // 高さを固定して横列を揃える
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(12)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// プレビュー用
struct PopupView_Previews: PreviewProvider {
    static var previews: some View {
        PopupView(url: URL(string: "https://example.com")!, onSelect: { _ in }, onCancel: {})
    }
}
