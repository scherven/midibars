import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: ProjectStore
    let onOpen: (UUID) -> Void

    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var hoveringID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("midibars")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Projects")
                        .font(.largeTitle.bold())
                }

                Spacer()

                Button {
                    newProjectName = ""
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(24)

            Divider()

            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.projects) { project in
                            ProjectCard(
                                project: project,
                                isHovering: hoveringID == project.id,
                                onOpen: { onOpen(project.id) },
                                onDelete: { store.delete(project) }
                            )
                            .onHover { hovering in
                                hoveringID = hovering ? project.id : nil
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(name: $newProjectName) {
                let config = ProjectConfig(name: newProjectName.isEmpty ? "Untitled" : newProjectName)
                store.save(config)
                showingNewProject = false
                onOpen(config.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No projects yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Create a new project to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
