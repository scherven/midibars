import Foundation

func formatTime(_ seconds: Double) -> String {
    let total = Int(max(seconds, 0))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

func clampedPercent(_ value: Double) -> Double {
    min(max(value, 0), 100)
}

let scaleNumberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f
}()
