import SwiftUI

private let paneWidth: CGFloat = 540

private struct PaneFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: paneWidth)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable private var store = SettingsStore.shared
    @State private var isDefault = DefaultApp.isDefault
    @State private var cliInstalled = CommandLineTool.isInstalled
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        PaneFrame {
            Section("Markdown files") {
                LabeledContent(isDefault ? "Legible is the default app for Markdown files." : "Legible is not the default app for Markdown files.") {
                    Button("Use Legible for Markdown Files…") {
                        DefaultApp.makeDefault { error in
                            isDefault = DefaultApp.isDefault
                            if let error { message = error.localizedDescription }
                        }
                    }
                    .disabled(isDefault)
                }
            }
            Section("Command line") {
                LabeledContent(cliInstalled ? "The `legible` command is installed in ~/.local/bin." : "The `legible` command is not installed.") {
                    Button(cliInstalled ? "Reinstall" : "Install") {
                        do {
                            try CommandLineTool.install()
                            message = "Installed \(CommandLineTool.installURL.path). Make sure ~/.local/bin is on your PATH."
                        } catch {
                            message = error.localizedDescription
                        }
                        cliInstalled = CommandLineTool.isInstalled
                    }
                }
                Text("Usage: legible README.md, or pipe Markdown in with legible -")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Restore windows from last time", isOn: $store.settings.restoreWindows)
            }
            Section("Settings file") {
                LabeledContent(store.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button("Reveal Settings File") { store.revealFile() }
                }
                if let error = store.fileError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Button("Reset to Defaults…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset every setting to its default?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { store.resetToDefaults() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("settings.toml will be rewritten. Comments and extra keys in it will be lost.")
                    }
            }
            if let message {
                Section { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultApp.isDefault
            cliInstalled = CommandLineTool.isInstalled
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable private var store = SettingsStore.shared
    private var themes: [Theme] { ThemeManager.shared.themes }

    var body: some View {
        PaneFrame {
            Section("Theme") {
                Picker("Theme", selection: $store.settings.theme) {
                    Text("Follow System").tag("system")
                    Divider()
                    ForEach(themes, id: \.id) { theme in
                        Text("\(theme.name)\(theme.appearance == .dark ? "  (dark)" : "")").tag(theme.id)
                    }
                }
                Picker("Light mode", selection: $store.settings.lightTheme) {
                    ForEach(themes.filter { $0.appearance == .light }, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Dark mode", selection: $store.settings.darkTheme) {
                    ForEach(themes.filter { $0.appearance == .dark }, id: \.id) { Text($0.name).tag($0.id) }
                }
                Text("Themes are CSS files. Add your own in View › Theme › Show User Themes Folder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Type") {
                TextField("Body font", text: $store.settings.fontBody, prompt: Text("Theme default"))
                TextField("Code font", text: $store.settings.fontMono, prompt: Text("Theme default"))
                OptionalNumber(label: "Size", value: $store.settings.fontSize, unit: "px", range: 10...40, step: 1)
                OptionalDecimal(label: "Line height", value: $store.settings.lineHeight, range: 1.1...2.4, step: 0.05)
                OptionalNumber(label: "Measure", value: $store.settings.measure, unit: "ch", range: 40...140, step: 2)
                Text("Zero or blank keeps the theme's own value.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Zoom") {
                Slider(value: $store.settings.zoom, in: Zoom.minimum...Zoom.maximum, step: 0.1) {
                    Text("Zoom")
                } minimumValueLabel: { Text("70%") } maximumValueLabel: { Text("250%") }
                LabeledContent("Current", value: "\(Int((store.settings.zoom * 100).rounded()))%")
            }
        }
    }
}

/// An integer field where 0 means "theme default", with a stepper and a Default button.
private struct OptionalNumber: View {
    let label: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent(label) {
            HStack {
                Stepper(value: $value, in: 0...range.upperBound, step: step) {
                    Text(value == 0 ? "Theme default" : "\(value) \(unit)").monospacedDigit()
                }
                .onChange(of: value) { old, new in
                    if old == 0 && new > 0 { value = range.lowerBound + (new > range.lowerBound ? 0 : 0) }
                    if new > 0 && new < range.lowerBound { value = old == 0 ? range.lowerBound : 0 }
                }
                if value != 0 { Button("Default") { value = 0 } }
            }
        }
    }
}

private struct OptionalDecimal: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(label) {
            HStack {
                Stepper(value: $value, in: 0...range.upperBound, step: step) {
                    Text(value == 0 ? "Theme default" : String(format: "%.2f", value)).monospacedDigit()
                }
                .onChange(of: value) { old, new in
                    if new > 0 && new < range.lowerBound { value = old == 0 ? range.lowerBound : 0 }
                }
                if value != 0 { Button("Default") { value = 0 } }
            }
        }
    }
}

// MARK: - Reading

struct ReadingPane: View {
    @Bindable private var store = SettingsStore.shared

    var body: some View {
        PaneFrame {
            Section {
                Toggle("Show the table of contents sidebar when a document opens", isOn: $store.settings.tocSidebar)
                Toggle("Show reading time", isOn: $store.settings.showReadingTime)
            }
            Section("Links") {
                Toggle("Open links to other Markdown files in Legible", isOn: $store.settings.openMarkdownLinksInLegible)
                Text("External links always open in your default browser.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Files") {
                Toggle("Re-render when the file changes on disk", isOn: $store.settings.liveReload)
            }
        }
    }
}

// MARK: - Editor

struct EditorPane: View {
    @Bindable private var store = SettingsStore.shared

    var body: some View {
        PaneFrame {
            Section("Font") {
                TextField("Font", text: $store.settings.editorFont, prompt: Text("System monospace"))
                Stepper(value: $store.settings.editorFontSize, in: 9...32) {
                    LabeledContent("Size", value: "\(store.settings.editorFontSize) pt")
                }
            }
            Section("Behaviour") {
                Toggle("Wrap long lines", isOn: $store.settings.editorWrap)
                Toggle("Keep the editor and preview scrolled together", isOn: $store.settings.scrollSync)
            }
        }
    }
}

// MARK: - Garnish

struct GarnishPane: View {
    @Bindable private var store = SettingsStore.shared

    var body: some View {
        PaneFrame {
            Section {
                Toggle("Hold the garnish", isOn: $store.settings.garnishHold)
                Text("Served plain.").font(.callout).foregroundStyle(.secondary)
            }
            if !store.settings.garnishHold {
                Section {
                    Toggle("Mascot", isOn: $store.settings.garnishMascot)
                    Toggle("Copy feedback", isOn: $store.settings.garnishCopyMessages)
                    Toggle("Reading time in coffees", isOn: $store.settings.garnishCoffees)
                    Toggle("Deadpan empty states and About", isOn: $store.settings.garnishDeadpan)
                    Toggle("End-of-document ornament", isOn: $store.settings.garnishOrnament)
                    Toggle("Theme-matched Dock icon", isOn: $store.settings.garnishDockIcon)
                }
                Section {
                    Toggle("Housetrained", isOn: $store.settings.garnishHousetrained)
                }
            }
        }
    }
}
