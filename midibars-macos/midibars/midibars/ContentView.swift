import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ProjectStore
    @StateObject private var project = ProjectState()
    @State private var openProjectID: UUID?

    var body: some View {
        Group {
            if let projectID = openProjectID {
                EditorView(
                    project: project,
                    projectID: projectID,
                    onClose: { saveAndClose() }
                )
                .environmentObject(store)
            } else {
                ProjectsView(onOpen: { id in openProject(id: id) })
                    .environmentObject(store)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openProjectID != nil)
    }

    private func openProject(id: UUID) {
        guard let config = store.project(for: id) else { return }
        project.restore(from: config)
        openProjectID = id
    }

    private func saveAndClose() {
        if let id = openProjectID, var config = store.project(for: id) {
            project.save(into: &config)
            store.save(config)
        }
        project.reset()
        openProjectID = nil
    }
}

// MARK: - Editor View

struct EditorView: View {
    @ObservedObject var project: ProjectState
    let projectID: UUID
    let onClose: () -> Void
    @EnvironmentObject var store: ProjectStore

    private var projectName: String {
        store.project(for: projectID)?.name ?? "Untitled"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Projects")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(projectName)
                    .font(.headline)

                Spacer()

                Button {
                    saveProject()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down.on.square")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                SidebarView(project: project)
                Divider()
                VStack(spacing: 0) {
                    VideoCanvasView(project: project)
                    if project.midiURL != nil {
                        Divider()
                        MIDIPianoRollPanel(project: project)
                            .frame(height: 120)
                    }
                    if project.audioURL != nil {
                        Divider()
                        AudioWaveformPanel(project: project)
                            .frame(height: 120)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: project.midiURL != nil)
            .animation(.easeInOut(duration: 0.25), value: project.audioURL != nil)
        }
    }

    private func saveProject() {
        if var config = store.project(for: projectID) {
            project.save(into: &config)
            store.save(config)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectStore())
}
