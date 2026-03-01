import SwiftUI

struct PianoOverlayView: View {
    @ObservedObject var project: ProjectState
    @State private var activeCorner: Int?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Canvas { context, canvasSize in
                    let tl = denorm(project.pianoTopLeft, in: canvasSize)
                    let tr = denorm(project.pianoTopRight, in: canvasSize)
                    let bl = denorm(project.pianoBottomLeft, in: canvasSize)
                    let br = denorm(project.pianoBottomRight, in: canvasSize)

                    var outline = Path()
                    outline.move(to: tl)
                    outline.addLine(to: tr)
                    outline.addLine(to: br)
                    outline.addLine(to: bl)
                    outline.closeSubpath()

                    if project.isSettingPiano {
                        context.fill(outline, with: .color(.white.opacity(0.08)))
                    }

                    if !project.isSettingPiano {
                        drawActiveNotes(context: context, tl: tl, tr: tr, bl: bl, br: br)
                    }

                    context.stroke(outline, with: .color(.white.opacity(0.6)), lineWidth: 1.5)

                    if project.isSettingPiano {
                        for point in [tl, tr, bl, br] {
                            drawHandle(context: context, at: point)
                        }
                    }
                }

                if project.isSettingPiano {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if activeCorner == nil {
                                        activeCorner = closestCornerIndex(
                                            to: value.startLocation, in: size
                                        )
                                    }
                                    guard let idx = activeCorner else { return }
                                    let clamped = CGPoint(
                                        x: max(0, min(1, value.location.x / size.width)),
                                        y: max(0, min(1, value.location.y / size.height))
                                    )
                                    setCorner(idx, to: clamped)
                                }
                                .onEnded { _ in
                                    activeCorner = nil
                                }
                        )
                }
            }
        }
        .allowsHitTesting(project.isSettingPiano)
    }

    // MARK: - Drawing

    private func drawHandle(context: GraphicsContext, at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        let circle = Path(ellipseIn: rect)
        context.fill(circle, with: .color(.white))
        context.stroke(circle, with: .color(.blue), lineWidth: 2)
    }

    private func drawActiveNotes(
        context: GraphicsContext, tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint
    ) {
        guard !project.activeMIDINotes.isEmpty else { return }

        let low = project.pianoLowNote
        let high = project.pianoHighNote
        let numKeys = high - low + 1
        guard numKeys > 0 else { return }

        for pitch in project.activeMIDINotes {
            let keyIndex = Int(pitch) - low
            guard keyIndex >= 0, keyIndex < numKeys else { continue }

            let t0 = CGFloat(keyIndex) / CGFloat(numKeys)
            let t1 = CGFloat(keyIndex + 1) / CGFloat(numKeys)

            let keyTL = lerp(tl, tr, t: t0)
            let keyTR = lerp(tl, tr, t: t1)
            let keyBL = lerp(bl, br, t: t0)
            let keyBR = lerp(bl, br, t: t1)

            var keyPath = Path()
            keyPath.move(to: keyTL)
            keyPath.addLine(to: keyTR)
            keyPath.addLine(to: keyBR)
            keyPath.addLine(to: keyBL)
            keyPath.closeSubpath()

            let isBlack = [1, 3, 6, 8, 10].contains(Int(pitch) % 12)
            let color: Color = isBlack ? .blue : .cyan
            context.fill(keyPath, with: .color(color.opacity(0.6)))
        }
    }

    // MARK: - Corner Interaction

    private func closestCornerIndex(to point: CGPoint, in size: CGSize) -> Int {
        let corners = [
            denorm(project.pianoTopLeft, in: size),
            denorm(project.pianoTopRight, in: size),
            denorm(project.pianoBottomLeft, in: size),
            denorm(project.pianoBottomRight, in: size),
        ]
        var bestIdx = 0
        var bestDist = CGFloat.infinity
        for (i, c) in corners.enumerated() {
            let d = hypot(c.x - point.x, c.y - point.y)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    private func setCorner(_ index: Int, to point: CGPoint) {
        switch index {
        case 0: project.pianoTopLeft = point
        case 1: project.pianoTopRight = point
        case 2: project.pianoBottomLeft = point
        case 3: project.pianoBottomRight = point
        default: break
        }
    }

    // MARK: - Helpers

    private func denorm(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
