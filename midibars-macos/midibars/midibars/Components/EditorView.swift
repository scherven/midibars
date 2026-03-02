import SwiftUI

struct EditorView: View {
    @ObservedObject var project: ProjectState
    let projectID: UUID
    let onClose: () -> Void
    let lastSavedAt: Date?
    let lastSaveWasAuto: Bool
    let onManualSave: () -> Void
    @EnvironmentObject var store: ProjectStore
    @SceneStorage("midibars.midiViewerExpanded") private var midiViewerExpanded: Bool = true
    @SceneStorage("midibars.audioViewerExpanded") private var audioViewerExpanded: Bool = true

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

                if lastSavedAt != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text(lastSaveWasAuto ? "Auto-saved" : "Saved")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    onManualSave()
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
                        MIDIPianoRollPanel(project: project, isExpanded: $midiViewerExpanded)
                            .frame(height: midiViewerExpanded ? 120 : 32)
                    }
                    if project.audioURL != nil {
                        Divider()
                        AudioWaveformPanel(project: project, isExpanded: $audioViewerExpanded)
                            .frame(height: audioViewerExpanded ? 120 : 32)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: project.midiURL != nil)
            .animation(.easeInOut(duration: 0.25), value: project.audioURL != nil)
        }
    }

}
