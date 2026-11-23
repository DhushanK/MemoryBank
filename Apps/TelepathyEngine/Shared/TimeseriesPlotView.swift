import SwiftUI

struct TimeseriesPlotView: View {
    let title: String
    let channelCount: Int
    let seriesForChannel: (Int) -> [Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if channelCount == 0 {
                ContentUnavailableView("No tap data", systemImage: "waveform", description: Text("Start live playback or scrub a session."))
            } else {
                GeometryReader { geo in
                    let rowHeight = max(28, geo.size.height / CGFloat(max(channelCount, 1)))
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(0..<channelCount, id: \.self) { ch in
                                ChannelStrip(
                                    label: String(format: "ch%02d", ch),
                                    values: seriesForChannel(ch),
                                    height: rowHeight - 4
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ChannelStrip: View {
    let label: String
    let values: [Float]
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
            TimelineCanvas(values: values)
                .frame(height: height)
        }
    }
}

private struct TimelineCanvas: View {
    let values: [Float]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let mid = size.height / 2
            let amp = size.height * 0.42
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                let y = mid - CGFloat(v) * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.cyan), lineWidth: 1)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: mid))
            baseline.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(baseline, with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
