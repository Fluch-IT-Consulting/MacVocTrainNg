import SwiftUI

/// The root of the app: opens the deck it showed last at launch (#285), and otherwise
/// offers to choose one. The open deck lies on top, see `DeckScreen`; going back closes
/// it.
struct StartScreen: View {
    @State private var deck: OpenDeck?
    @State private var isChoosing = false
    @State private var hasReopened = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Deck Open", systemImage: "rectangle.stack")
            } description: {
                Text("Decks are created in MacVocTrain on the Mac. Open one it saved, e.g. in iCloud Drive.")
            } actions: {
                Button("Open Deck…") { isChoosing = true }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle(Text(verbatim: "VocTrain"))
            .navigationDestination(item: $deck) { deck in
                DeckScreen(deck: deck)
            }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.vocabularyDeck]) { result in
            if case let .success(url) = result {
                openDeck(at: url)
            }
        }
        .onOpenURL(perform: openDeck(at:))
        .onAppear(perform: reopen)
        .onChange(of: deck) { previous, _ in
            if let previous {
                Task { await previous.close() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: deck?.suspend()
            case .active: deck?.resume()
            default: break
            }
        }
    }

    /// Opens the deck remembered last, once, at launch.
    private func reopen() {
        guard !hasReopened else { return }
        hasReopened = true
        if deck == nil, let url = LastDeck().resolve() {
            deck = OpenDeck(url: url)
        }
    }

    private func openDeck(at url: URL) {
        guard deck?.url != url else { return }
        deck = OpenDeck(url: url)
    }
}

/// An open deck: its overview once the file is read, else why it couldn't be.
///
/// Each document gets a deck view of its own: when another device changed the file,
/// `OpenDeck` brings a new document, and a study session would go on changing the old
/// one, which nobody saves. The `VersionMerger` stays with the deck, so it can keep what
/// the old document held that the file lacks. The deck view shows what the merger
/// reports: an alert from here would come while the session leaves the screen, and get
/// lost.
private struct DeckScreen: View {
    var deck: OpenDeck

    var body: some View {
        Group {
            if let document = deck.document {
                DeckView(document: document, fileURL: deck.url, isEditable: deck.isEditable, merger: deck.merger, undoManager: deck.undoManager)
                    .id(ObjectIdentifier(document))
                    .onAppear { LastDeck().remember(deck.url) }
            } else if let failure = deck.failure {
                ContentUnavailableView("The deck could not be opened", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: deck.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
