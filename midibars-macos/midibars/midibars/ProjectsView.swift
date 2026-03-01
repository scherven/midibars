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

// MARK: - Project Card

private struct ProjectCard: View {
    let project: ProjectConfig
    let isHovering: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if project.hasVideo {
                        Image(systemName: "film")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if project.hasAudio {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if project.hasMIDI {
                        Image(systemName: "pianokeys")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if isHovering {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isHovering)

                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(project.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    + Text(" ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovering ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete \"\(project.name)\"?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - New Project Sheet

private struct NewProjectSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(onCreate)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
