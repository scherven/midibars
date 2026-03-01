import SwiftUI

struct ProjectCard: View {
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
