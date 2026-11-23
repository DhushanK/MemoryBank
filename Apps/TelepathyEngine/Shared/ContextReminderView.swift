import SwiftUI
import LLMBridge

struct ContextReminderView: View {
    let prediction: PredictionPayload?

    var body: some View {
        GroupBox("Context Reminder") {
            if let prediction {
                VStack(alignment: .leading, spacing: 8) {
                    Text(prediction.predictedText)
                        .font(.title3.weight(.semibold))
                    HStack {
                        Text(String(format: "%.0f%% confidence", prediction.confidence * 100))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(prediction.engine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(prediction.sourceCitation)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waiting for decoder output…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
