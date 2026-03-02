import SwiftUI

/// Renders text overlay items on the canvas with fade in/out based on video time.
/// Selected items show a drag handle and can be repositioned directly on the canvas.
struct TextOverlayView: View {
    @ObservedObject var project: ProjectState
    let canvasSize: CGSize

    private var currentVideoTime: Double {
        (project.videoDuration * (project.videoPercent / 100.0))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(project.textOverlays) { item in
                textView(for: item)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func textView(for item: TextOverlayItem) -> some View {
        let opacity = opacityFor(item)
        let isSelected = project.selectedTextOverlayID == item.id
        let font: Font = project.globalTextFontName.isEmpty
            ? .system(size: item.fontSize, weight: .medium)
            : .custom(project.globalTextFontName, size: item.fontSize)
        return Text(item.text)
            .font(font)
            .foregroundStyle(
                Color(
                    red: item.colorRed,
                    green: item.colorGreen,
                    blue: item.colorBlue
                )
                .opacity(opacity)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
            )
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .offset(x: -4, y: -4)
                }
            }
            .position(
                x: canvasSize.width * item.positionX,
                y: canvasSize.height * item.positionY
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        project.selectedTextOverlayID = item.id
                        guard let index = project.textOverlays.firstIndex(where: { $0.id == item.id }) else { return }
                        let newX = max(0, min(1, value.location.x / canvasSize.width))
                        let newY = max(0, min(1, value.location.y / canvasSize.height))
                        project.textOverlays[index].positionX = newX
                        project.textOverlays[index].positionY = newY
                    }
            )
    }

    private func opacityFor(_ item: TextOverlayItem) -> Double {
        let t = currentVideoTime
        let (fadeInAt, fadeInDuration, fadeOutAt, fadeOutDuration): (Double, Double, Double, Double)
        if item.fadeInOutWithOthers {
            fadeInAt = project.globalTextFadeInAt
            fadeInDuration = project.globalTextFadeInDuration
            fadeOutAt = project.globalTextFadeOutAt
            fadeOutDuration = project.globalTextFadeOutDuration
        } else {
            fadeInAt = item.fadeInAt
            fadeInDuration = item.fadeInDuration
            fadeOutAt = item.fadeOutAt
            fadeOutDuration = item.fadeOutDuration
        }
        if t < fadeInAt - fadeInDuration {
            return 0
        }
        if t < fadeInAt {
            let progress = fadeInDuration > 0
                ? (t - (fadeInAt - fadeInDuration)) / fadeInDuration
                : 1
            return min(1, max(0, progress))
        }
        if fadeOutAt > 0 && t >= fadeOutAt {
            if t >= fadeOutAt + fadeOutDuration {
                return 0
            }
            let progress = fadeOutDuration > 0
                ? (t - fadeOutAt) / fadeOutDuration
                : 1
            return 1 - min(1, max(0, progress))
        }
        return 1
    }
}
