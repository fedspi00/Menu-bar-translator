import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: Store
    @ObservedObject var loginItem: LoginItem

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            inputArea
            Divider()
            outputArea
            Divider()
            footer
        }
        .frame(width: 380, height: 372)
        .onChange(of: store.openCount) { _ in focusInput() }
        .onAppear { focusInput() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            LanguageMenu(
                selection: $store.source,
                includeAuto: !store.autoFlip,
                recents: store.recents,
                title: sourceTitle
            )

            Button(action: store.swapLanguages) {
                Image(systemName: store.autoFlip ? "arrow.left.arrow.right" : "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(store.autoFlip
                  ? "Translates into whichever side isn't detected. Swap (⌘S)"
                  : "Swap languages (⌘S)")

            LanguageMenu(
                selection: $store.target,
                includeAuto: false,
                recents: store.recents,
                title: Languages.name(for: store.target)
            )

            Spacer(minLength: 0)

            optionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// With "Detect" selected, show what was actually detected so the
    /// direction never looks like a black box.
    private var sourceTitle: String {
        guard store.source == Languages.autoCode else {
            return Languages.name(for: store.source)
        }
        if let from = store.direction?.from, from != Languages.autoCode {
            return "Detect · \(Languages.short(for: from))"
        }
        return "Detect"
    }

    private var autoFlipToggle: some View {
        Toggle("Translate either direction", isOn: $store.autoFlip)
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Translate as you type", isOn: $store.translateAsYouType)
            autoFlipToggle
            Toggle("Clear text when opened", isOn: $store.clearOnOpen)

            Divider()

            Toggle("Global shortcut (⌥⌘T)", isOn: $store.hotKeyEnabled)
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))

            Divider()

            Text("⌘⏎ translate · ⇧⌘C copy · ⇧⌘V paste & translate")
            Text("⌘S swap · ⌘K clear · esc close")

            Divider()

            Button("Quit Lingo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .foregroundStyle(.secondary)
        .help("Options")
    }

    // MARK: - Text areas

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            if store.input.isEmpty {
                Text("Type or paste text…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $store.input)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .focused($inputFocused)
        }
        .frame(height: 132)
        .background(Color.clear)
    }

    private var outputArea: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                Group {
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else if store.output.isEmpty {
                        Text("Translation")
                            .font(.system(size: 13))
                            .foregroundStyle(.quaternary)
                    } else {
                        Text(store.output)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
            }

            if store.isTranslating {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .padding(.trailing, 10)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 132)
        .background(Color.primary.opacity(0.035))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let direction = store.direction, !store.output.isEmpty {
                Text("\(Languages.short(for: direction.from)) → \(Languages.short(for: direction.to))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            footerButton("Paste", systemImage: "doc.on.clipboard", help: "Paste and translate (⇧⌘V)") {
                store.pasteAndTranslate()
            }

            footerButton("Clear", systemImage: "xmark.circle", help: "Clear (⌘K)") {
                store.clear()
                focusInput()
            }
            .disabled(store.input.isEmpty && store.output.isEmpty)

            footerButton(
                store.didCopy ? "Copied" : "Copy",
                systemImage: store.didCopy ? "checkmark" : "doc.on.doc",
                help: "Copy translation (⇧⌘C)"
            ) {
                store.copyOutput()
            }
            .disabled(store.output.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: - Helpers

    private func focusInput() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            inputFocused = true
            // Select whatever is already there so typing replaces it.
            if !store.input.isEmpty {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Language picker

private struct LanguageMenu: View {
    @Binding var selection: String
    let includeAuto: Bool
    let recents: [String]
    let title: String

    var body: some View {
        Menu {
            if includeAuto {
                item(code: Languages.autoCode, name: "Detect language")
                Divider()
            }
            if !recentCodes.isEmpty {
                Section("Recent") {
                    ForEach(recentCodes, id: \.self) { code in
                        item(code: code, name: Languages.name(for: code))
                    }
                }
                Divider()
            }
            Section("All languages") {
                ForEach(Languages.all) { language in
                    item(code: language.code, name: language.name)
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var recentCodes: [String] {
        recents.filter { $0 != selection }.prefix(5).map { $0 }
    }

    private func item(code: String, name: String) -> some View {
        Button {
            selection = code
        } label: {
            if code == selection {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }
}
