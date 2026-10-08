import AppKit

extension NSAlert {
    /// Shows a modal warning, e.g. when an import or export failed. The callers
    /// localize the title, so it stays in the String Catalog.
    @MainActor
    static func showWarning(_ title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
