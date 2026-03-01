import SwiftUI

struct PianoOverlayView: View {
    @ObservedObject var project: ProjectState
    @State private var activeCorner: Int?
    @State private var activeEdge: Int?

    private let blackKeyHeightRatio: CGFloat = 0.62
    private let blackKeyWidthRatio: Double = 0.55
    private let barLeadTime: Double = 2.0
    private let barMinHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Canvas { context, canvasSize in
                    let tl = denorm(project.pianoTopLeft, in: canvasSize)
                    let tr = denorm(project.pianoTopRight, in: canvasSize)
                    let bl = denorm(project.pianoBottomLeft, in: canvasSize)
                    let br = denorm(project.pianoBottomRight, in: canvasSize)

                    let edges = effectiveEdges()
                    let whiteNotes = Self.whiteNotes(low: project.pianoLowNote, high: project.pianoHighNote)
                    let blackNotes = Self.blackNotes(low: project.pianoLowNote, high: project.pianoHighNote)
                    let whiteIndexMap = Dictionary(uniqueKeysWithValues: whiteNotes.enumerated().map { ($1, $0) })

                    // 1) MIDI dropping bars (behind the piano)
                    if !project.isSettingPiano {
                        drawMidiBars(
                            context: context, tl: tl, tr: tr,
                            edges: edges, whiteIndexMap: whiteIndexMap
                        )
                    }

                    // 2) Semi-transparent fill when setting piano position
                    if project.isSettingPiano {
                        var fill = Path()
                        fill.move(to: tl)
                        fill.addLine(to: tr)
                        fill.addLine(to: br)
                        fill.addLine(to: bl)
                        fill.closeSubpath()
                        context.fill(fill, with: .color(.white.opacity(0.08)))
                    }

                    // 3) White key separator lines
                    let edgeOpacity: Double = project.isAdjustingKeys ? 0.5 : 0.3
                    for i in 0...whiteNotes.count {
                        let f = CGFloat(edges[i])
                        let top = lerp(tl, tr, t: f)
                        let bot = lerp(bl, br, t: f)
                        var line = Path()
                        line.move(to: top)
                        line.addLine(to: bot)
                        context.stroke(line, with: .color(.white.opacity(edgeOpacity)), lineWidth: 0.5)
                    }

                    // 4) Black key bodies
                    for note in blackNotes {
                        let (lf, rf) = blackKeyFracs(note: note, whiteIndexMap: whiteIndexMap, edges: edges)
                        guard lf < rf else { continue }
                        let path = quadPath(
                            leftF: lf, rightF: rf,
                            topG: 0, bottomG: Double(blackKeyHeightRatio),
                            tl: tl, tr: tr, bl: bl, br: br
                        )
                        context.fill(path, with: .color(Color(white: 0.12)))
                        context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                    }

                    // 5) Outer border
                    var outline = Path()
                    outline.move(to: tl)
                    outline.addLine(to: tr)
                    outline.addLine(to: br)
                    outline.addLine(to: bl)
                    outline.closeSubpath()
                    context.stroke(outline, with: .color(.white.opacity(0.6)), lineWidth: 1.5)

                    // 6) Corner handles
                    if project.isSettingPiano {
                        for point in [tl, tr, bl, br] {
                            drawHandle(context: context, at: point)
                        }
                    }

                    // 7) Edge adjustment: highlight active edge
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

        // Perpendicular direction pointing "up" from the piano top edge
        let dx = tr.x - tl.x
        let dy = tr.y - tl.y
        let lineLen = hypot(dx, dy)
        guard lineLen > 1 else { return }

        var upX = dy / lineLen
        var upY = -dx / lineLen
        if upY > 0 { upX = -upX; upY = -upY }

        // Spawn distance: how far bars travel from spawn point to the piano top edge.
        // Use the distance from the piano top-edge midpoint to the top of the canvas.
        let midY = (tl.y + tr.y) / 2
        let spawnDist: CGFloat = abs(upY) > 0.001 ? abs(midY / upY) : midY
        guard spawnDist > 1 else { return }

        let speed = spawnDist / CGFloat(barLeadTime)

        for note in midiData.notes {
            let start = note.startTime
            let dur = note.duration
            let pitch = Int(note.pitch)

            let noteH = max(barMinHeight, CGFloat(dur) * speed)
            let effectiveEnd = start + max(dur, Double(noteH / speed))

            guard currentTime >= start - barLeadTime, currentTime <= effectiveEnd else { continue }
            guard pitch >= project.pianoLowNote, pitch <= project.pianoHighNote else { continue }

            // Horizontal fractions for this key
            let lf: Double
            let rf: Double
            if Self.isBlack(pitch) {
                let fracs = blackKeyFracs(note: pitch, whiteIndexMap: whiteIndexMap, edges: edges)
                guard fracs.0 < fracs.1 else { continue }
                (lf, rf) = fracs
            } else {
                guard let idx = whiteIndexMap[pitch] else { continue }
                lf = edges[idx]
                rf = edges[idx + 1]
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

            let bL = CGPoint(x: pL.x + perpOff * upX, y: pL.y + perpOff * upY)
            let bR = CGPoint(x: pR.x + perpOff * upX, y: pR.y + perpOff * upY)
            let barTL = CGPoint(x: bL.x + curH * upX, y: bL.y + curH * upY)
            let barTR = CGPoint(x: bR.x + curH * upX, y: bR.y + curH * upY)

            var path = Path()
            path.move(to: bL)
            path.addLine(to: bR)
            path.addLine(to: barTR)
            path.addLine(to: barTL)
            path.closeSubpath()

            context.fill(path, with: .color(.red.opacity(0.8)))
        }
    }

    // MARK: - Key Layout

    private func effectiveEdges() -> [Double] {
        let count = Self.whiteNotes(low: project.pianoLowNote, high: project.pianoHighNote).count
        if project.pianoWhiteKeyEdges.count == count + 1 {
            return project.pianoWhiteKeyEdges
        }
        return Self.defaultEdges(whiteKeyCount: count)
    }

    static func defaultEdges(whiteKeyCount: Int) -> [Double] {
        guard whiteKeyCount > 0 else { return [0, 1] }
        return (0...whiteKeyCount).map { Double($0) / Double(whiteKeyCount) }
    }

    static func whiteNotes(low: Int, high: Int) -> [Int] {
        guard high >= low else { return [] }
        return (low...high).filter { !isBlack($0) }
    }

    static func blackNotes(low: Int, high: Int) -> [Int] {
        guard high >= low else { return [] }
        return (low...high).filter { isBlack($0) }
    }

    static func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note % 12)
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

    // MARK: - Geometry

    private func quadPath(
        leftF: Double, rightF: Double,
        topG: Double, bottomG: Double,
        tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint
    ) -> Path {
        let pTL = bilinear(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(leftF), g: CGFloat(topG))
        let pTR = bilinear(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(rightF), g: CGFloat(topG))
        let pBR = bilinear(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(rightF), g: CGFloat(bottomG))
        let pBL = bilinear(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(leftF), g: CGFloat(bottomG))

        var path = Path()
        path.move(to: pTL)
        path.addLine(to: pTR)
        path.addLine(to: pBR)
        path.addLine(to: pBL)
        path.closeSubpath()
        return path
    }

    private func bilinear(tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint, f: CGFloat, g: CGFloat) -> CGPoint {
        let top = lerp(tl, tr, t: f)
        let bot = lerp(bl, br, t: f)
        return lerp(top, bot, t: g)
    }

    private func denorm(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
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

    // MARK: - Edge Interaction

    private func fractionAlongTopEdge(point: CGPoint, in size: CGSize) -> Double {
        let tl = denorm(project.pianoTopLeft, in: size)
        let tr = denorm(project.pianoTopRight, in: size)
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
