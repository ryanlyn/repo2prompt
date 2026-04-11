import SwiftUI
import AppKit

@main
struct Repo2PromptApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Repo2Prompt") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Repo2Prompt",
                        .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        .credits: NSAttributedString(
                            string: "Turn any folder into a structured prompt for LLMs.",
                            attributes: [.foregroundColor: NSColor.labelColor]
                        )
                    ])
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .repo2PromptToggleSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    NotificationCenter.default.post(name: .repo2PromptOpenFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Prompt") {
                    NotificationCenter.default.post(name: .repo2PromptCopyPrompt, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
