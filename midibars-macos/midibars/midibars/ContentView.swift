import SwiftUI

private let lastOpenProjectIDKey = "midibars.lastOpenProjectID"

struct ContentView: View {
    @EnvironmentObject var store: ProjectStore
    @StateObject private var project = ProjectState()
    @State private var openProjectID: UUID?
    @State private var hasRestoredLastProject = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var lastSavedAt: Date?
    @State private var lastSaveWasAuto: Bool = false
    @State private var autoSaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let projectID = openProjectID {
                EditorView(
                    project: project,
                    projectID: projectID,
                    onClose: { saveAndClose() },
                    lastSavedAt: lastSavedAt,
                    lastSaveWasAuto: lastSaveWasAuto,
                    onManualSave: { performSave(autosave: false) }
                )
                .environmentObject(store)
            } else {
                ProjectsView(onOpen: { id in openProject(id: id) })
                    .environmentObject(store)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openProjectID != nil)
        .onChange(of: openProjectID) { _, newID in
            if newID != nil {
                startAutoSave()
            } else {
                stopAutoSave()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                performSave(autosave: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            project.stopPlayback()
            performSave(autosave: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            performSave(autosave: true)
        }
        .onAppear {
            guard !hasRestoredLastProject, openProjectID == nil else { return }
            hasRestoredLastProject = true
            guard let idString = UserDefaults.standard.string(forKey: lastOpenProjectIDKey),
                  let lastID = UUID(uuidString: idString),
                  store.project(for: lastID) != nil else { return }
            openProject(id: lastID)
        }
    }

    private func openProject(id: UUID) {
        guard let config = store.project(for: id) else { return }
        project.restore(from: config)
        openProjectID = id
        lastSavedAt = nil
        lastSaveWasAuto = false
        UserDefaults.standard.set(id.uuidString, forKey: lastOpenProjectIDKey)
    }

    private func startAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                performSave(autosave: true)
            }
        }
    }

    private func stopAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    private func performSave(autosave: Bool) {
        guard let id = openProjectID, var config = store.project(for: id) else { return }
        project.save(into: &config)
        store.save(config)
        lastSavedAt = Date()
        lastSaveWasAuto = autosave
    }

    private func saveAndClose() {
        performSave(autosave: false)
        project.reset()
        openProjectID = nil
        lastSavedAt = nil
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectStore())
}
