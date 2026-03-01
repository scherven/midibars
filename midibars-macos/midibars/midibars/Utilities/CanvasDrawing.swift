import SwiftUI

func drawVerticalLine(
    in context: GraphicsContext,
    size: CGSize,
    atPercent percent: Double,
    color: Color,
    lineWidth: CGFloat = 1.5
) {
    let x = size.width * CGFloat(percent / 100.0)
    var line = Path()
    line.move(to: CGPoint(x: x, y: 0))
    line.addLine(to: CGPoint(x: x, y: size.height))
    context.stroke(line, with: .color(color), lineWidth: lineWidth)
}
