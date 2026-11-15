import AppKit
import NaturalLanguage
import SwiftUI

/// All app state and preferences. Preferences persist to UserDefaults as they
/// change, so there is no separate settings window to keep in sync.
@MainActor
final class Store: ObservableObject {

    // MARK: Text

    @Published var input = "" {
        didSet { if input != oldValue { inputChanged() } }
    }
    @Published private(set) var output = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTranslating = false
    @Published private(set) var didCopy = false

    /// Direction actually used for the visible result, e.g. ("en", "fr").
    @Published private(set) var direction: (from: String, to: String)?

    /// Bumped whenever the panel opens, so the view can refocus the field.
    @Published var openCount = 0

    // MARK: Preferences

    @Published var source: String = Defaults.source {
        didSet {
            guard source != oldValue else { return }
            UserDefaults.standard.set(source, forKey: Keys.source)
            note(source)
            retranslate()
        }
    }

    @Published var target: String = Defaults.target {
        didSet {
            guard target != oldValue else { return }
            UserDefaults.standard.set(target, forKey: Keys.target)
            note(target)
            retranslate()
        }
    }

    /// With auto-flip on, the two pickers describe a pair rather than a fixed
    /// direction: whichever side the text is already in, it goes to the other.
    /// This is what makes EN⇄FR work without touching the pickers.
    @Published var autoFlip: Bool = true {
        didSet {
            UserDefaults.standard.set(autoFlip, forKey: Keys.autoFlip)
            // A pair needs two real languages; "Detect" only means something
            // in one-way mode.
            if autoFlip && source == Languages.autoCode { source = "en" }
            retranslate()
        }
    }

    @Published var translateAsYouType: Bool = true {
        didSet { UserDefaults.standard.set(translateAsYouType, forKey: Keys.live) }
    }

    @Published var clearOnOpen: Bool = false {
        didSet { UserDefaults.standard.set(clearOnOpen, forKey: Keys.clearOnOpen) }
    }

    @Published var hotKeyEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: Keys.hotKey)
            onHotKeyPreferenceChange?(hotKeyEnabled)
        }
    }

    @Published private(set) var recents: [String] = Defaults.recents

    var onHotKeyPreferenceChange: ((Bool) -> Void)?

    private var pending: Task<Void, Never>?
    private var copyFlash: Task<Void, Never>?
    private var lastTranslated: String?
    private var generation = 0

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Keys.source),
           stored == Languages.autoCode || Languages.exists(stored) {
            source = stored
        }
        if let stored = defaults.string(forKey: Keys.target), Languages.exists(stored) {
            target = stored
        }
        if defaults.object(forKey: Keys.autoFlip) != nil {
            autoFlip = defaults.bool(forKey: Keys.autoFlip)
        }
        if autoFlip && source == Languages.autoCode {
            source = Defaults.source
        }
        if source == target {
            target = source == "en" ? "fr" : "en"
        }
        if defaults.object(forKey: Keys.live) != nil {
            translateAsYouType = defaults.bool(forKey: Keys.live)
        }
        if defaults.object(forKey: Keys.clearOnOpen) != nil {
            clearOnOpen = defaults.bool(forKey: Keys.clearOnOpen)
        }
        if defaults.object(forKey: Keys.hotKey) != nil {
            hotKeyEnabled = defaults.bool(forKey: Keys.hotKey)
        }
        if let stored = defaults.stringArray(forKey: Keys.recents) {
            recents = stored.filter(Languages.exists)
        }
    }

    // MARK: - Actions

    func panelDidOpen() {
        if clearOnOpen { clear() }
        openCount += 1
    }

    func translateNow() {
        pending?.cancel()
        lastTranslated = nil
        start(delay: 0)
    }

    func swapLanguages() {
        if source == Languages.autoCode {
            // Nothing explicit on the left to swap, so use the direction that
            // produced the current result.
            guard let resolved = direction, resolved.from != Languages.autoCode else { return }
            source = resolved.to
            target = resolved.from
        } else {
            let previousSource = source
            source = target
            target = previousSource
        }
        // Swapping usually means "send this translation back", so promote the
        // result into the input.
        if !output.isEmpty {
            input = output
        }
    }

    func clear() {
        pending?.cancel()
        lastTranslated = nil
        input = ""
        output = ""
        errorMessage = nil
        direction = nil
        isTranslating = false
    }

    @discardableResult
    func copyOutput() -> Bool {
        guard !output.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)

        didCopy = true
        copyFlash?.cancel()
        copyFlash = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
        return true
    }

    func pasteAndTranslate() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        input = text
        translateNow()
    }

    // MARK: - Translation pipeline

    private func inputChanged() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pending?.cancel()
            output = ""
            errorMessage = nil
            direction = nil
            isTranslating = false
            lastTranslated = nil
            return
        }
        guard translateAsYouType else { return }
        start(delay: 0.45)
    }

    private func retranslate() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastTranslated = nil
        start(delay: 0.1)
    }

    private func start(delay: TimeInterval) {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        pending?.cancel()
        pending = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            await self.perform(text)
        }
    }

    private func perform(_ text: String) async {
        let route = resolveRoute(for: text)
        let signature = "\(route.from)|\(route.to)|\(text)"
        if signature == lastTranslated { return }

        // A superseded request must not clear the spinner out from under the
        // request that replaced it.
        generation += 1
        let generation = self.generation
        defer { if generation == self.generation { isTranslating = false } }

        isTranslating = true
        errorMessage = nil

        do {
            var result = try await GoogleTranslate.translate(text, from: route.from, to: route.to)
            guard !Task.isCancelled else { return }

            var from = result.detected ?? route.from
            var to = route.to

            // Google may disagree with the local detector. If it says the text
            // was already in the language we translated into, send it to the
            // other side of the pair rather than showing the input unchanged.
            if autoFlip, let detected = result.detected, detected == to, otherSide(of: to) != detected {
                let other = otherSide(of: to)
                result = try await GoogleTranslate.translate(text, from: Languages.autoCode, to: other)
                guard !Task.isCancelled else { return }
                from = result.detected ?? detected
                to = other
            }

            // Short words that exist in both languages ("Bonjour", "Merci")
            // get detected as the wrong one and handed straight back. An
            // unchanged result means the guess was wrong, so force the other
            // side of the pair before settling for it.
            if autoFlip, unchanged(result.text, from: text), otherSide(of: to) != to {
                let other = otherSide(of: to)
                let forced = try await GoogleTranslate.translate(text, from: to, to: other)
                guard !Task.isCancelled else { return }
                if !unchanged(forced.text, from: text) {
                    result = forced
                    from = to
                    to = other
                }
            }

            output = result.text
            direction = (from, to)
            lastTranslated = signature
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The side of the pair that isn't `code`.
    private func otherSide(of code: String) -> String {
        code == source ? target : source
    }

    private func unchanged(_ translated: String, from original: String) -> Bool {
        let a = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = original.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Picks the direction for a piece of text. In one-way mode that is just
    /// the picker values. In pair mode the on-device recognizer decides which
    /// side of the pair the text is on, so the common EN⇄FR round trip costs
    /// no extra request to Google.
    private func resolveRoute(for text: String) -> (from: String, to: String) {
        guard autoFlip else { return (source, target) }
        let detected = LocalDetector.detect(text)
        return (Languages.autoCode, detected == target ? source : target)
    }

    // MARK: - Recents

    private func note(_ code: String) {
        guard Languages.exists(code) else { return }
        var updated = recents.filter { $0 != code }
        updated.insert(code, at: 0)
        recents = Array(updated.prefix(6))
        UserDefaults.standard.set(recents, forKey: Keys.recents)
    }

    private enum Keys {
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let autoFlip = "autoFlip"
        static let live = "translateAsYouType"
        static let clearOnOpen = "clearOnOpen"
        static let hotKey = "hotKeyEnabled"
        static let recents = "recentLanguages"
    }

    private enum Defaults {
        static let source = "en"
        static let target = "fr"
        static let recents = ["en", "fr"]
    }
}

/// On-device language identification, used only to pick a direction.
enum LocalDetector {
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = hypotheses.first else { return nil }

        // Short text is easy to misidentify; don't flip direction on a guess.
        let threshold = trimmed.count < 12 ? 0.75 : 0.45
        guard confidence >= threshold else { return nil }
        return Languages.normalize(language.rawValue)
    }
}
