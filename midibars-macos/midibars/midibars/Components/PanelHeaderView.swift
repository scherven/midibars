import SwiftUI

struct PanelHeaderView: View {
    let icon: String
    let title: String
    var isExpanded: Binding<Bool>? = nil

    var body: some View {
        Group {
            if let isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    headerContent(isExpanded: isExpanded.wrappedValue)
                }
                .buttonStyle(.plain)
            } else {
                headerContent(isExpanded: nil)
            }
        }
    }

    @ViewBuilder
    private func headerContent(isExpanded: Bool?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
