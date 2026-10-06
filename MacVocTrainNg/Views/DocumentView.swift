import SwiftUI
import VocabCore

/// The content of a document window: the card list or the statistics, or a study
/// session that temporarily takes over the whole window.
struct DocumentView: View {
    enum Screen: Hashable {
        case cards
        case statistics
    }

    @ObservedObject var document: VocabularyDocument
    @Environment(\.undoManager) private var undoManager
    @State private var screen: Screen = .cards
    @State private var study: StudyViewModel?
    @State private var showingOptions = false

    var body: some View {
        Group {
            if let study {
                StudyView(model: study) { self.study = nil }
            } else {
                switch screen {
                case .cards: CardListView(document: document)
                case .statistics: StatisticsView(document: document)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .toolbar {
            if study == nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $screen) {
                        Label("Cards", systemImage: "rectangle.stack").tag(Screen.cards)
                        Label("Statistics", systemImage: "chart.bar.xaxis").tag(Screen.statistics)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    StartStudyButton(document: document, action: startSession)
                }
                ToolbarItem {
                    Button {
                        showingOptions = true
                    } label: {
                        Label("Learning Options", systemImage: "slider.horizontal.3")
                    }
                    .help("Learning Options")
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            DeckOptionsView(document: document)
        }
        .focusedSceneValue(\.deckActions, DeckActions(
            isStudying: study != nil,
            canStartSession: study == nil && document.dueCount() > 0,
            startSession: startSession,
            show: { screen = $0 },
            showOptions: { showingOptions = true }
        ))
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
                NSDocumentController.shared.documents.forEach { $0.save(nil) }
            }
        }
    }
    #endif

    private func startSession() {
        guard study == nil else { return }
        let model = StudyViewModel(document: document)
        if !model.isFinished {
            study = model
        }
    }
}

/// "Study" button showing how many cards are due. Re-evaluated every minute
/// because cards become due as time passes.
private struct StartStudyButton: View {
    @ObservedObject var document: VocabularyDocument
    var action: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let due = document.dueCount(at: context.date)
            Button(action: action) {
                Label(due > 0 ? "Study (\(due))" : "Study", systemImage: "graduationcap")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(due == 0)
            .help(due > 0 ? "Start a study session" : "No cards are due")
        }
    }
}

// MARK: - Menu commands

/// Actions of the focused document window, for the menu bar.
struct DeckActions {
    var isStudying: Bool
    var canStartSession: Bool
    var startSession: () -> Void
    var show: (DocumentView.Screen) -> Void
    var showOptions: () -> Void
}

private struct DeckActionsKey: FocusedValueKey {
    typealias Value = DeckActions
}

extension FocusedValues {
    var deckActions: DeckActions? {
        get { self[DeckActionsKey.self] }
        set { self[DeckActionsKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.deckActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import MacVocTrain 1 Document…") {
                LegacyImport.run()
            }
        }

        CommandMenu("Study") {
            Button("Start Session") { actions?.startSession() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions?.canStartSession != true)

            Divider()

            Button("Cards") { actions?.show(.cards) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(actions == nil || actions?.isStudying == true)
            Button("Statistics") { actions?.show(.statistics) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(actions == nil || actions?.isStudying == true)

            Divider()

            Button("Learning Options…") { actions?.showOptions() }
                .disabled(actions == nil || actions?.isStudying == true)
        }
    }
}
