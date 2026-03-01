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
