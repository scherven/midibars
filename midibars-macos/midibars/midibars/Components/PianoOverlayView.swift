import SwiftUI

struct PianoOverlayView: View {
    @ObservedObject var project: ProjectState
    @State private var activeCorner: Int?
    @State private var activeEdge: Int?

    private let blackKeyHeightRatio: CGFloat = 0.62
    private let blackKeyWidthRatio: Double = 0.55
    private let whiteBarWidthRatio: Double = 0.6
    private let barLeadTime: Double = 2.0
    private let barMinHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Canvas { context, canvasSize in
                    let tl = denormalize(project.pianoTopLeft, in: canvasSize)
                    let tr = denormalize(project.pianoTopRight, in: canvasSize)
                    let bl = denormalize(project.pianoBottomLeft, in: canvasSize)
                    let br = denormalize(project.pianoBottomRight, in: canvasSize)

                    let edges = effectiveEdges()
                    let whites = whiteNotes(low: project.pianoLowNote, high: project.pianoHighNote)
                    let blacks = blackNotes(low: project.pianoLowNote, high: project.pianoHighNote)
                    let whiteIndexMap = Dictionary(uniqueKeysWithValues: whites.enumerated().map { ($1, $0) })

                    if !project.isSettingPiano {
                        drawMidiBars(
                            context: context, tl: tl, tr: tr,
                            edges: edges, whiteIndexMap: whiteIndexMap
                        )
                    }

                    let showOutlines = project.showPianoOverlay || project.isSettingPiano || project.isAdjustingKeys

                    if showOutlines {
                        if project.isSettingPiano {
                            var fill = Path()
                            fill.move(to: tl)
                            fill.addLine(to: tr)
                            fill.addLine(to: br)
                            fill.addLine(to: bl)
                            fill.closeSubpath()
                            context.fill(fill, with: .color(.white.opacity(0.08)))
                        }

                        let edgeOpacity: Double = project.isAdjustingKeys ? 0.5 : 0.3
                        for i in 0...whites.count {
                            let f = CGFloat(edges[i])
                            let top = lerp(tl, tr, t: f)
                            let bot = lerp(bl, br, t: f)
                            var line = Path()
                            line.move(to: top)
                            line.addLine(to: bot)
                            context.stroke(line, with: .color(.black.opacity(edgeOpacity)), lineWidth: 0.5)
                        }

                        for note in blacks {
                            let (lf, rf) = blackKeyFracs(note: note, whiteIndexMap: whiteIndexMap, edges: edges)
                            guard lf < rf else { continue }
                            let path = quadrilateralPath(
                                leftF: lf, rightF: rf,
                                topG: 0, bottomG: Double(blackKeyHeightRatio),
                                tl: tl, tr: tr, bl: bl, br: br
                            )
                            context.fill(path, with: .color(Color(white: 0.12)))
                            context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                        }

                        var outline = Path()
                        outline.move(to: tl)
                        outline.addLine(to: tr)
                        outline.addLine(to: br)
                        outline.addLine(to: bl)
                        outline.closeSubpath()
                        context.stroke(outline, with: .color(.white.opacity(0.6)), lineWidth: 1.5)

                        if project.isSettingPiano {
                            for point in [tl, tr, bl, br] {
                                drawHandle(context: context, at: point)
                            }
                        }

                        if project.isAdjustingKeys, let idx = activeEdge, idx > 0, idx < edges.count - 1 {
                            let f = CGFloat(edges[idx])
                            let top = lerp(tl, tr, t: f)
                            let bot = lerp(bl, br, t: f)
                            var line = Path()
                            line.move(to: top)
                            line.addLine(to: bot)
                            context.stroke(line, with: .color(.yellow.opacity(0.9)), lineWidth: 2)
                            let r: CGFloat = 4
                            context.fill(Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: r * 2, height: r * 2)),
                                         with: .color(.yellow))
                            context.fill(Path(ellipseIn: CGRect(x: bot.x - r, y: bot.y - r, width: r * 2, height: r * 2)),
                                         with: .color(.yellow))
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
                                        activeCorner = closestCornerIndex(to: value.startLocation, in: size)
                                    }
                                    guard let idx = activeCorner else { return }
                                    let clamped = CGPoint(
                                        x: max(0, min(1, value.location.x / size.width)),
                                        y: max(0, min(1, value.location.y / size.height))
                                    )
                                    setCorner(idx, to: clamped)
                                }
                                .onEnded { _ in activeCorner = nil }
                        )
                }

                if project.isAdjustingKeys {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if activeEdge == nil {
                                        project.ensurePianoEdgesPopulated()
                                        let frac = fractionAlongTopEdge(point: value.startLocation, in: size)
                                        activeEdge = closestInternalEdge(fraction: frac)
                                    }
                                    guard let idx = activeEdge else { return }
                                    guard idx > 0, idx < project.pianoWhiteKeyEdges.count - 1 else { return }
                                    let frac = fractionAlongTopEdge(point: value.location, in: size)
                                    let minGap = 0.002
                                    let lo = project.pianoWhiteKeyEdges[idx - 1] + minGap
                                    let hi = project.pianoWhiteKeyEdges[idx + 1] - minGap
                                    project.pianoWhiteKeyEdges[idx] = max(lo, min(hi, frac))
                                }
                                .onEnded { _ in activeEdge = nil }
                        )
                }
            }
        }
        .allowsHitTesting(project.isSettingPiano || project.isAdjustingKeys)
    }

    // MARK: - MIDI Bars

    private func drawMidiBars(
        context: GraphicsContext,
        tl: CGPoint, tr: CGPoint,
        edges: [Double],
        whiteIndexMap: [Int: Int]
    ) {
        guard let midiData = project.midiData, midiData.duration > 0 else { return }

        let currentTime = midiData.duration * (project.midiPlaybackPercent / 100.0)

        let dx = tr.x - tl.x
        let dy = tr.y - tl.y
        let lineLen = hypot(dx, dy)
        guard lineLen > 1 else { return }

        var upX = dy / lineLen
        var upY = -dx / lineLen
        if upY > 0 { upX = -upX; upY = -upY }

        let rightX = dx / lineLen
        let rightY = dy / lineLen

        let midY = (tl.y + tr.y) / 2
        let spawnDist: CGFloat = abs(upY) > 0.001 ? abs(midY / upY) : midY
        guard spawnDist > 1 else { return }

        let speed = spawnDist / CGFloat(barLeadTime)
        let cr = CGFloat(project.barConfig.cornerRadius)

        for note in midiData.notes {
            let start = note.startTime
            let dur = note.duration
            let pitch = Int(note.pitch)

            let noteH = max(barMinHeight, CGFloat(dur) * speed)
            let effectiveEnd = start + max(dur, Double(noteH / speed))

            guard currentTime >= start - barLeadTime, currentTime <= effectiveEnd else { continue }
            guard pitch >= project.pianoLowNote, pitch <= project.pianoHighNote else { continue }

            let lf: Double
            let rf: Double
            if isBlackKey(pitch) {
                let fracs = blackKeyFracs(note: pitch, whiteIndexMap: whiteIndexMap, edges: edges)
                guard fracs.0 < fracs.1 else { continue }
                (lf, rf) = fracs
            } else {
                guard let idx = whiteIndexMap[pitch] else { continue }
                let keyLeft = edges[idx]
                let keyRight = edges[idx + 1]
                let inset = (keyRight - keyLeft) * (1 - whiteBarWidthRatio) / 2
                lf = keyLeft + inset
                rf = keyRight - inset
            }

            let pL = lerp(tl, tr, t: CGFloat(lf))
            let pR = lerp(tl, tr, t: CGFloat(rf))

            let perpOff: CGFloat
            let curH: CGFloat

            if currentTime < start {
                let progress = CGFloat((currentTime - (start - barLeadTime)) / barLeadTime)
                perpOff = spawnDist * (1 - progress)
                curH = noteH
            } else {
                let elapsed = CGFloat(currentTime - start)
                let overshoot = speed * elapsed
                perpOff = 0
                curH = max(0, noteH - overshoot)
            }

            guard curH > 0.5 else { continue }

            let barWidth = hypot(pR.x - pL.x, pR.y - pL.y)
            guard barWidth > 0.5 else { continue }

            let originX = pL.x + perpOff * upX
            let originY = pL.y + perpOff * upY

            let clampedCR = min(cr, barWidth / 2, curH / 2)

            let localRect = CGRect(x: 0, y: 0, width: barWidth, height: curH)
            let localPath = Path(roundedRect: localRect, cornerRadius: clampedCR)

            let transform = CGAffineTransform(
                a: rightX, b: rightY,
                c: upX,    d: upY,
                tx: originX, ty: originY
            )
            let path = localPath.applying(transform)

            context.fill(path, with: .color(.red.opacity(0.8)))
        }
    }

    // MARK: - Key Layout

    private func effectiveEdges() -> [Double] {
        let count = whiteNotes(low: project.pianoLowNote, high: project.pianoHighNote).count
        if project.pianoWhiteKeyEdges.count == count + 1 {
            return project.pianoWhiteKeyEdges
        }
        return defaultPianoEdges(whiteKeyCount: count)
    }

    private func blackKeyFracs(note: Int, whiteIndexMap: [Int: Int], edges: [Double]) -> (Double, Double) {
        guard let leftIdx = whiteIndexMap[note - 1],
              leftIdx + 2 < edges.count else {
            return (0, 0)
        }
        let boundary = edges[leftIdx + 1]
        let leftWidth = edges[leftIdx + 1] - edges[leftIdx]
        let rightWidth = edges[leftIdx + 2] - edges[leftIdx + 1]
        let avgWidth = (leftWidth + rightWidth) / 2
        let bw = avgWidth * blackKeyWidthRatio
        return (boundary - bw / 2, boundary + bw / 2)
    }

    // MARK: - Corner Interaction

    private func drawHandle(context: GraphicsContext, at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        let circle = Path(ellipseIn: rect)
        context.fill(circle, with: .color(.white))
        context.stroke(circle, with: .color(.blue), lineWidth: 2)
    }

    private func closestCornerIndex(to point: CGPoint, in size: CGSize) -> Int {
        let corners = [
            denormalize(project.pianoTopLeft, in: size),
            denormalize(project.pianoTopRight, in: size),
            denormalize(project.pianoBottomLeft, in: size),
            denormalize(project.pianoBottomRight, in: size),
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

    // MARK: - Edge Interaction

    private func fractionAlongTopEdge(point: CGPoint, in size: CGSize) -> Double {
        let tl = denormalize(project.pianoTopLeft, in: size)
        let tr = denormalize(project.pianoTopRight, in: size)
        let dx = tr.x - tl.x
        let dy = tr.y - tl.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return 0 }
        let t = ((point.x - tl.x) * dx + (point.y - tl.y) * dy) / len2
        return Double(max(0, min(1, t)))
    }

    private func closestInternalEdge(fraction: Double) -> Int? {
        let edges = project.pianoWhiteKeyEdges
        guard edges.count > 2 else { return nil }
        var bestIdx = 1
        var bestDist = Double.infinity
        for i in 1..<(edges.count - 1) {
            let d = abs(edges[i] - fraction)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }
}
