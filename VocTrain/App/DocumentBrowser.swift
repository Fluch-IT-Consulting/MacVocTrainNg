import UIKit

/// The document browser of the `DocumentGroup`, which opens a deck as if it was picked
/// there (#282).
///
/// SwiftUI can't open a document from code on iOS: `openDocument` exists only on macOS.
/// But the scene shows a `UIDocumentBrowserViewController`, and its delegate, which
/// SwiftUI provides, opens the document it is told was picked. Through iOS 17 the
/// browser is the root of the window; since iOS 18 the root may be a
/// `UIDocumentViewController` that brings it in its launch options. If no browser takes
/// the deck, nothing opens and the browser stays, as without this.
@MainActor
enum DocumentBrowser {
    /// Hands `url` to the first browser whose delegate opens picked documents; `false`
    /// if there is none.
    static func open(_ url: URL) -> Bool {
        for browser in all() {
            let handled: Void? = browser.delegate?.documentBrowser?(browser, didPickDocumentsAt: [url])
            if handled != nil {
                return true
            }
        }
        return false
    }

    /// Whether a browser is in a window and done coming on screen. A deck opened while
    /// the browser is still being presented over the launch view shows a blank page on
    /// the iPhone: SwiftUI builds the deck screen but never puts it into the document's
    /// view controller (#282).
    static var isOnScreen: Bool {
        all().contains { browser in
            browser.viewIfLoaded?.window != nil && !browser.isBeingPresented && browser.transitionCoordinator == nil
        }
    }

    /// Whether a document is open or opening. SwiftUI keeps its UIDocument to itself,
    /// but it is among the file presenters of the app, see `FileVersionStore.save()`.
    static var hasOpenDocument: Bool {
        NSFileCoordinator.filePresenters.contains { $0 is UIDocument }
    }

    /// The document browsers in the windows of the app, outermost first.
    static func all() -> [UIDocumentBrowserViewController] {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.compactMap(\.rootViewController).flatMap(browsers(in:))
    }

    private static func browsers(in controller: UIViewController) -> [UIDocumentBrowserViewController] {
        var browsers: [UIDocumentBrowserViewController] = []
        if let browser = controller as? UIDocumentBrowserViewController {
            browsers.append(browser)
        }
        if #available(iOS 18, *), let documentController = controller as? UIDocumentViewController {
            browsers.append(documentController.launchOptions.browserViewController)
        }
        for child in controller.children {
            browsers += Self.browsers(in: child)
        }
        if let presented = controller.presentedViewController {
            browsers += Self.browsers(in: presented)
        }
        return browsers
    }
}
