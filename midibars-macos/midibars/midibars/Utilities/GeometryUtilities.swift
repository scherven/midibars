import SwiftUI

func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: point.x * size.width, y: point.y * size.height)
}

func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

func bilinearInterpolate(
    tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint,
    f: CGFloat, g: CGFloat
) -> CGPoint {
    let top = lerp(tl, tr, t: f)
    let bot = lerp(bl, br, t: f)
    return lerp(top, bot, t: g)
}

func quadrilateralPath(
    leftF: Double, rightF: Double,
    topG: Double, bottomG: Double,
    tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint
) -> Path {
    let pTL = bilinearInterpolate(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(leftF), g: CGFloat(topG))
    let pTR = bilinearInterpolate(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(rightF), g: CGFloat(topG))
    let pBR = bilinearInterpolate(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(rightF), g: CGFloat(bottomG))
    let pBL = bilinearInterpolate(tl: tl, tr: tr, bl: bl, br: br, f: CGFloat(leftF), g: CGFloat(bottomG))

    var path = Path()
    path.move(to: pTL)
    path.addLine(to: pTR)
    path.addLine(to: pBR)
    path.addLine(to: pBL)
    path.closeSubpath()
    return path
}

// MARK: - Key Position on Piano Top Edge

func keyFractionOnTopEdge(
    pitch: Int,
    edges: [Double],
    whiteIndexMap: [Int: Int],
    blackKeyWidthRatio: Double
) -> CGFloat? {
    if isBlackKey(pitch) {
        guard let leftIdx = whiteIndexMap[pitch - 1],
              leftIdx + 2 < edges.count else { return nil }
        let boundary = edges[leftIdx + 1]
        let leftWidth = edges[leftIdx + 1] - edges[leftIdx]
        let rightWidth = edges[leftIdx + 2] - edges[leftIdx + 1]
        let avgWidth = (leftWidth + rightWidth) / 2
        let bw = avgWidth * blackKeyWidthRatio
        let lf = boundary - bw / 2
        let rf = boundary + bw / 2
        guard lf < rf else { return nil }
        return CGFloat((lf + rf) / 2)
    } else {
        guard let idx = whiteIndexMap[pitch], idx + 1 < edges.count else { return nil }
        return CGFloat((edges[idx] + edges[idx + 1]) / 2)
    }
}

/// Returns the (left, right) fractional positions of a black key's bar, or nil if not computable.
func blackKeyBoundaries(
    note: Int, whiteIndexMap: [Int: Int], edges: [Double], widthRatio: Double
) -> (Double, Double)? {
    guard let leftIdx = whiteIndexMap[note - 1], leftIdx + 2 < edges.count else { return nil }
    let boundary = edges[leftIdx + 1]
    let avgWidth = ((edges[leftIdx + 1] - edges[leftIdx]) + (edges[leftIdx + 2] - edges[leftIdx + 1])) / 2
    let bw = avgWidth * widthRatio
    return (boundary - bw / 2, boundary + bw / 2)
}

/// Shared black key width ratio (black key width as fraction of adjacent white key average width).
let blackKeyWidthRatio: Double = 0.55

func pianoTopEdgePoint(
    fraction: CGFloat,
    topLeft: CGPoint,
    topRight: CGPoint
) -> CGPoint {
    lerp(topLeft, topRight, t: fraction)
}
