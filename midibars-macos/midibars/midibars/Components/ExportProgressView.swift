import SwiftUI

struct ExportProgressView: View {
    @ObservedObject var exporter: VideoExporter
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if exporter.isExporting {
                exportingContent
            } else if exporter.isFinished {
                finishedContent
            } else if let errorMessage = exporter.errorMessage {
                errorContent(errorMessage)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private var exportingContent: some View {
        VStack(spacing: 16) {
            ProgressView(value: exporter.progress)
                .progressViewStyle(.linear)

            Text("Exporting… \(String(format: "%.2f", exporter.progress * 100))%")
                .font(.headline)
                .monospacedDigit()

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(estimatedTimeRemaining)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Cancel") {
                exporter.cancel()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var estimatedTimeRemaining: String {
        guard let start = exporter.exportStartDate, exporter.progress > 0.02 else {
            return "Estimating…"
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = elapsed * (1 - exporter.progress) / exporter.progress
        if remaining < 60 {
            return "About \(Int(ceil(remaining))) sec remaining"
        } else if remaining < 3600 {
            let mins = Int(remaining / 60)
            let secs = Int(remaining.truncatingRemainder(dividingBy: 60))
            return "About \(mins) min \(secs) sec remaining"
        } else {
            let hrs = Int(remaining / 3600)
            let mins = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "About \(hrs) hr \(mins) min remaining"
        }
    }

    private var finishedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Export Complete")
                .font(.headline)

            if let url = exporter.outputURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 12) {
                Button("Open File") {
                    exporter.openOutputFile()
                }
                .buttonStyle(.borderedProminent)

                Button("Reveal in Finder") {
                    exporter.revealInFinder()
                }
                .buttonStyle(.bordered)
            }

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Export Failed")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
