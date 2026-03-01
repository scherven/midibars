import SwiftUI

/// Renders text overlay items on the canvas with fade in/out based on video time.
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
        .allowsHitTesting(false)
    }

    private func textView(for item: TextOverlayItem) -> some View {
        let opacity = opacityFor(item)
        return Text(item.text)
            .font(.system(size: item.fontSize, weight: .medium))
            .foregroundStyle(
                Color(
                    red: item.colorRed,
                    green: item.colorGreen,
                    blue: item.colorBlue
                )
                .opacity(opacity)
            )
            .position(
                x: canvasSize.width * item.positionX,
                y: canvasSize.height * item.positionY
            )
    }

    private func opacityFor(_ item: TextOverlayItem) -> Double {
        let t = currentVideoTime
        if t < item.fadeInAt - item.fadeInDuration {
            return 0
        }
        if t < item.fadeInAt {
            let progress = item.fadeInDuration > 0
                ? (t - (item.fadeInAt - item.fadeInDuration)) / item.fadeInDuration
                : 1
            return min(1, max(0, progress))
        }
        if item.fadeOutAt > 0 && t >= item.fadeOutAt {
            if t >= item.fadeOutAt + item.fadeOutDuration {
                return 0
            }
            let progress = item.fadeOutDuration > 0
                ? (t - item.fadeOutAt) / item.fadeOutDuration
                : 1
            return 1 - min(1, max(0, progress))
        }
        return 1
    }
}
