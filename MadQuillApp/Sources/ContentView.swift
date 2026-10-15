import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var setup = SetupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MadQuill is ready")
                .font(.title2.weight(.semibold))
            Text("MadQuill adds Markdown previews to Finder Quick Look. Keep this app in Applications; you can close it after setup.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Extension registration", systemImage: setup.registrationSucceeded ? "checkmark.circle.fill" : "hourglass")
                    .foregroundStyle(setup.registrationSucceeded ? .green : .primary)
                Label("Quick Look cache refresh", systemImage: setup.cacheRefreshSucceeded ? "checkmark.circle.fill" : "hourglass")
                    .foregroundStyle(setup.cacheRefreshSucceeded ? .green : .primary)
            }
            .font(.subheadline)

            if !setup.lastMessage.isEmpty {
                Text(setup.lastMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("How to test")
                    .font(.headline)
                Text("1. Open Finder and select a .md file")
                Text("2. Press Space to open Quick Look")
                Text("3. If needed, reopen this app and click “Refresh setup”")
            }
            .font(.subheadline)

            HStack(spacing: 10) {
                Button("Open Extensions Settings") {
                    setup.openExtensionsSettings()
                }
                Button("Refresh setup") {
                    setup.runSetup(force: true)
                }
                Button("Close MadQuill") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 340)
        .onAppear {
            setup.runSetup(force: false)
        }
    }
}

final class SetupViewModel: ObservableObject {
    @Published var registrationSucceeded = false
    @Published var cacheRefreshSucceeded = false
    @Published var lastMessage = ""

    private let setupVersion = 1
    private let defaultsKey = "madquill.setup.version"

    func runSetup(force: Bool) {
        if !force {
            let doneVersion = UserDefaults.standard.integer(forKey: defaultsKey)
            if doneVersion >= setupVersion {
                registrationSucceeded = true
                cacheRefreshSucceeded = true
                lastMessage = "Setup already completed on this Mac."
                return
            }
        }

        lastMessage = "Running setup..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let registration = self.registerExtension()
            let reset = self.resetQuickLook()
            DispatchQueue.main.async {
                self.registrationSucceeded = registration.success
                self.cacheRefreshSucceeded = reset.success
                self.lastMessage = [registration.message, reset.message].joined(separator: "\n")
                if registration.success && reset.success {
                    UserDefaults.standard.set(self.setupVersion, forKey: self.defaultsKey)
                }
            }
        }
    }

    func openExtensionsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.extensions"
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        lastMessage = "Could not open Extensions settings automatically."
    }

    private func registerExtension() -> (success: Bool, message: String) {
        guard let pluginURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MarkdownQuickLookExtension.appex") else {
            return (false, "Extension bundle not found inside the app.")
        }
        return runCommand(
            launchPath: "/usr/bin/pluginkit",
            arguments: ["-a", pluginURL.path],
            successMessage: "Extension registration refreshed.",
            failurePrefix: "Extension registration failed"
        )
    }

    private func resetQuickLook() -> (success: Bool, message: String) {
        let resetDaemon = runCommand(
            launchPath: "/usr/bin/qlmanage",
            arguments: ["-r"],
            successMessage: "Quick Look daemon reloaded.",
            failurePrefix: "qlmanage -r failed"
        )
        let resetCache = runCommand(
            launchPath: "/usr/bin/qlmanage",
            arguments: ["-r", "cache"],
            successMessage: "Quick Look cache reset.",
            failurePrefix: "qlmanage -r cache failed"
        )
        let ok = resetDaemon.success && resetCache.success
        return (ok, "\(resetDaemon.message)\n\(resetCache.message)")
    }

    private func runCommand(
        launchPath: String,
        arguments: [String],
        successMessage: String,
        failurePrefix: String
    ) -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0 {
                return (true, successMessage)
            }
            let detail = err.isEmpty ? out : err
            return (false, "\(failurePrefix): \(detail)")
        } catch {
            return (false, "\(failurePrefix): \(error.localizedDescription)")
        }
    }
}
