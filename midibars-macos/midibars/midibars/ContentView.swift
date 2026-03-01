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

#Preview {
    ContentView()
        .environmentObject(ProjectStore())
}
