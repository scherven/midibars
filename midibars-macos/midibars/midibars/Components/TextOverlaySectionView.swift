import SwiftUI

/// Text / Titles section for the sidebar. Each overlay is an expandable card with its own options.
struct TextOverlaySectionView: View {
    @ObservedObject var project: ProjectState
    @State private var expandedOverlayIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            addButton

            globalFadeSection

            ForEach(project.textOverlays) { item in
                overlayCard(item: item)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Global Fade (single setting for all titles that "fade with others")

    private var globalFadeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Fade In / Out")
                Spacer()
                Text("Shared when toggled on")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                labeledField("In At (s)", value: $project.globalTextFadeInAt, width: 44)
                labeledField("In Dur", value: $project.globalTextFadeInDuration, width: 44)
            }
            HStack {
                sectionLabel("Fade Out")
                Spacer()
                Text("0 = stay on")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                labeledField("Out At (s)", value: $project.globalTextFadeOutAt, width: 44)
                labeledField("Out Dur", value: $project.globalTextFadeOutDuration, width: 44)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            let newItem = TextOverlayItem()
            project.textOverlays.append(newItem)
            project.selectedTextOverlayID = newItem.id
            expandedOverlayIDs.insert(newItem.id)
        } label: {
            Label("Add Text Box", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }

    // MARK: - Overlay Card

    private func overlayCard(item: TextOverlayItem) -> some View {
        let itemID = item.id
        return DisclosureGroup(isExpanded: expandedBinding(for: itemID)) {
            overlayEditor(binding: overlayBinding(for: itemID))
        } label: {
            overlayCardHeader(item: item)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            project.selectedTextOverlayID == itemID
                                ? Color.accentColor.opacity(0.6)
                                : Color.primary.opacity(0.08),
                            lineWidth: project.selectedTextOverlayID == itemID ? 1.5 : 1
                        )
                )
        )
    }

    private func overlayCardHeader(item: TextOverlayItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: item.colorRed, green: item.colorGreen, blue: item.colorBlue))
                .frame(width: 10, height: 10)

            Text(item.text.isEmpty ? "Untitled" : String(item.text.prefix(24)))
                .lineLimit(1)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Text("\(Int(item.fontSize))pt")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if project.selectedTextOverlayID == item.id {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { project.selectedTextOverlayID = item.id }
    }

    private func overlayEditor(binding: Binding<TextOverlayItem>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Text")
                TextField("Enter title...", text: binding.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            Divider()

            // Appearance
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Appearance")
                HStack(spacing: 12) {
                    Picker("Size", selection: binding.fontSize) {
                        ForEach([18.0, 24.0, 32.0, 40.0, 48.0, 56.0, 64.0, 72.0, 96.0, 120.0], id: \.self) { size in
                            Text("\(Int(size)) pt").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    ColorPicker("", selection: rgbBinding(
                        red: binding.colorRed,
                        green: binding.colorGreen,
                        blue: binding.colorBlue
                    ), supportsOpacity: false)
                }
            }

            Divider()

            // Position (hint about canvas dragging)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("Position")
                    Spacer()
                    Text("Drag on canvas to move")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    labeledField("X", value: binding.positionX, width: 44)
                    labeledField("Y", value: binding.positionY, width: 44)
                }
            }

            Divider()

            // Fade timing: use global or this overlay's own
            Toggle("Fade in/out with others", isOn: binding.fadeInOutWithOthers)
                .font(.caption)

            if !binding.wrappedValue.fadeInOutWithOthers {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("This title only")
                    HStack(spacing: 8) {
                        labeledField("In At (s)", value: binding.fadeInAt, width: 44)
                        labeledField("In Dur", value: binding.fadeInDuration, width: 44)
                    }
                    HStack(spacing: 8) {
                        labeledField("Out At (s)", value: binding.fadeOutAt, width: 44)
                        labeledField("Out Dur", value: binding.fadeOutDuration, width: 44)
                    }
                }
            }

            Divider()

            // Remove
            Button(role: .destructive) {
                if let item = project.textOverlays.first(where: { $0.id == binding.wrappedValue.id }) {
                    expandedOverlayIDs.remove(item.id)
                    project.textOverlays.removeAll { $0.id == item.id }
                    project.selectedTextOverlayID = project.textOverlays.first?.id
                }
            } label: {
                Label("Remove Title", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func labeledField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .font(.caption)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedOverlayIDs.contains(id) },
            set: { if $0 { expandedOverlayIDs.insert(id) } else { expandedOverlayIDs.remove(id) } }
        )
    }

    private func overlayBinding(for id: UUID) -> Binding<TextOverlayItem> {
        Binding(
            get: { project.textOverlays.first(where: { $0.id == id }) ?? TextOverlayItem() },
            set: { newValue in
                if let idx = project.textOverlays.firstIndex(where: { $0.id == id }) {
                    project.textOverlays[idx] = newValue
                }
            }
        )
    }

    private func rgbBinding(red: Binding<Double>, green: Binding<Double>, blue: Binding<Double>) -> Binding<Color> {
        Binding<Color>(
            get: { Color(red: red.wrappedValue, green: green.wrappedValue, blue: blue.wrappedValue) },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    red.wrappedValue = Double(components.redComponent)
                    green.wrappedValue = Double(components.greenComponent)
                    blue.wrappedValue = Double(components.blueComponent)
                }
            }
        )
    }
}
