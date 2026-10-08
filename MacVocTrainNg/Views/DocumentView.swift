import SwiftUI
import VocabCore

/// The content of a document window: the card list or the statistics, or a
/// session that temporarily takes over the whole window.
///
/// Shows one document for its whole life: the window gives each document a view of
/// its own, see `MacVocTrainApp`.
struct DocumentView: View {
    enum Screen: String {
        case cards
        case statistics
    }

    @ObservedObject var document: VocabularyDocument
    /// Where the document is saved; `nil` until it is saved for the first time.
    var fileURL: URL?
    /// `false` while the deck can only be viewed, e.g. an old version in the version
    /// browser or a file that can't be written. Nothing then changes the deck or starts
    /// a session; the controls say so by being disabled.
    var isEditable: Bool
    /// The document's undo manager, which SwiftUI hands only to views. The document
    /// gets it from here. A sheet's environment holds the undo manager of the sheet's
    /// own window instead (#48).
    @Environment(\.undoManager) private var undoManager
    /// Survives quitting when the window is restored; the session doesn't.
    @SceneStorage("screen") private var screen: Screen = .cards
    @State private var session: SessionViewModel?
    @State private var showingOptions = false
    @State private var importPreview: CardImport.Preview?

    var body: some View {
        Group {
            if let session {
                SessionView(model: session) { self.session = nil }
            } else {
                switch screen {
                case .cards: CardListView(document: document, isEditable: isEditable)
                case .statistics: StatisticsView(document: document)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .toolbar {
            if session == nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $screen) {
                        Label("Cards", systemImage: "rectangle.stack").tag(Screen.cards)
                        Label("Statistics", systemImage: "chart.bar.xaxis").tag(Screen.statistics)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    StartStudyButton(dueCards: document.dueCards, action: startSession)
                        .disabled(!isEditable)
                }
                ToolbarItem {
                    Button {
                        showingOptions = true
                    } label: {
                        Label("Learning Options", systemImage: "slider.horizontal.3")
                    }
                    .help("Learning Options")
                    .disabled(!isEditable)
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            DeckOptionsView(document: document)
        }
        .sheet(item: $importPreview) { preview in
            ImportPreviewView(document: document, preview: preview)
        }
        .onChange(of: undoManager, initial: true, giveUndoManagerToDocument)
        .focusedSceneValue(
            \.deckActions,
            DeckActions(
                isInSession: session != nil,
                isEditable: isEditable,
                canStartSession: isEditable && session == nil && document.dueCards.count > 0,
                startSession: startSession,
                show: { screen = $0 },
                showOptions: { showingOptions = true },
                importCards: importCards,
                exportCards: exportCards
            )
        )
        #if DEBUG
        .onAppear(perform: applyDebugLaunchArguments)
        #endif
    }

    #if DEBUG
    /// Development aids for checking the app without clicking through it:
    /// `-debugScreen statistics|study|options` opens a screen,
    /// `-debugSave YES` saves all open documents shortly after opening.
    private func applyDebugLaunchArguments() {
        switch UserDefaults.standard.string(forKey: "debugScreen") {
        case "statistics": screen = .statistics
        case "study": startSession()
        case "options": showingOptions = true
        default: break
        }
        if UserDefaults.standard.bool(forKey: "debugSave") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for openDocument in NSDocumentController.shared.documents {
                    openDocument.save(nil)
                }
            }
        }
    }
    #endif

    private func giveUndoManagerToDocument() {
        document.undoManager = undoManager
    }

    private func importCards() {
        guard isEditable else { return }
        importPreview = CardImport.chooseFile(existing: document.deck.cards, created: document.clock.now)
    }

    private func exportCards() {
        CardExport.run(
            cards: document.deck.cards,
            calendar: document.calendar,
            suggestedName: fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Cards")
        )
    }

    private func startSession() {
        guard isEditable, session == nil else { return }
        let model = SessionViewModel(document: document)
        if !model.isFinished {
            session = model
        }
    }
}

/// "Study" button showing how many cards are due.
private struct StartStudyButton: View {
    var dueCards: DueCardCounter
    var action: () -> Void

    var body: some View {
        let due = dueCards.count
        Button(action: action) {
            Label(due > 0 ? "Study (\(due))" : "Study", systemImage: "graduationcap")
                .labelStyle(.titleAndIcon)
        }
        .disabled(due == 0)
        .help(due > 0 ? "Start a study session" : "No cards are due")
    }
}
