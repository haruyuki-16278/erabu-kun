import SwiftUI
import AppKit

@main
struct TestApp: App {
    private var menuBarIcon: NSImage {
        let image = NSImage()
        image.size = NSSize(width: 18, height: 18)
        return image
    }
    var body: some Scene {
        MenuBarExtra {
            Button("Quit") {}
        } label: {
            Image(nsImage: menuBarIcon)
        }
    }
}
