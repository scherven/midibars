import SwiftUI

struct CropSlider: View {
    let label: String
    @Binding var value: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: 0...1.0)
                .controlSize(.small)
            TextField("", value: percentageBinding, format: .number.precision(.fractionLength(0...1)))
                .font(.caption)
                .monospacedDigit()
                .textFieldStyle(.plain)
                .frame(width: 32, alignment: .trailing)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentageBinding: Binding<Double> {
        Binding(
            get: { Double(value * 100) },
            set: { value = CGFloat(clampedPercent($0) / 100) }
        )
    }
}
