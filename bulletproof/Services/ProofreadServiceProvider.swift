import AppKit

/// Entry points for the two NSServices declared in Info.plist. Method names
/// must match the NSMessage values ("proofreadInPlace", "proofreadToClipboard").
final class ProofreadServiceProvider: NSObject {
    private let appState: AppState
    private let notifier = UserNotifier()

    init(appState: AppState) {
        self.appState = appState
    }

    /// Editable targets only (declares return types): replaces the selection.
    @objc func proofreadInPlace(_ pboard: NSPasteboard, userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let corrected = proofread(pboard: pboard, error: error) else { return }
        // The selection is still on screen during the callback; the actual
        // replacement happens after we return, hence the delayed flash.
        let flashRect = SelectionLocator.selectionScreenRect()
        pboard.clearContents()
        pboard.setString(corrected, forType: .string)
        if let flashRect {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                SuccessFlashController.shared.flash(over: flashRect)
            }
        }
    }

    /// Works anywhere text is selectable: result goes to the general pasteboard.
    @objc func proofreadToClipboard(_ pboard: NSPasteboard, userData: String?,
                                    error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let corrected = proofread(pboard: pboard, error: error) else { return }
        let general = NSPasteboard.general
        general.clearContents()
        general.setString(corrected, forType: .string)
        notifier.post(title: "Proofread complete", body: "Corrected text copied - press ⌘V to paste.")
    }

    private func proofread(pboard: NSPasteboard,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) -> String? {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = ProofreadingError.emptyInput.localizedDescription as NSString
            return nil
        }
        let engine = appState.makeEngine()
        appState.activity.begin()
        switch SyncBridge.run(timeout: 55, { try await engine.proofread(text) }) {
        case .success(let corrected):
            appState.activity.end(success: true)
            return corrected
        case .failure(let failure):
            appState.activity.end(success: false)
            error.pointee = failure.localizedDescription as NSString
            notifier.post(title: "Proofread failed", body: failure.localizedDescription)
            return nil
        }
    }
}
