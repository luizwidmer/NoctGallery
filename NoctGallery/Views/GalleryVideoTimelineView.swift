import SwiftUI

struct GalleryVideoTimelineView: View {
    @EnvironmentObject private var model: GalleryViewModel
    let asset: PhotoAssetRecord
    @Binding var time: Double
    @Binding var edits: GalleryShareEdits
    let selectedID: UUID?
    var onSeek: () -> Void
    @State private var data: GalleryTimelineData?
    @State private var error: String?
    private var duration: Double { max(0.1, asset.duration) }
    private var keys: [GalleryCoverKeyframe] { edits.redactions.first { $0.id == selectedID }?.keyframes ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(data.frames) { frame in
                                if let image = UIImage(data: frame.jpeg) { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width / 12, height: 56).clipped() }
                            }
                        }
                        Canvas { context, size in
                            let start = edits.trimStart / duration * size.width
                            let end = (edits.trimEnd ?? duration) / duration * size.width
                            context.fill(Path(CGRect(x: 0, y: 0, width: start, height: size.height)), with: .color(.black.opacity(0.6)))
                            context.fill(Path(CGRect(x: end, y: 0, width: max(0, size.width - end), height: size.height)), with: .color(.black.opacity(0.6)))
                            for i in stride(from: 0, to: keys.count, by: max(1, keys.count / 200)) {
                                let x = keys[i].time / duration * size.width
                                context.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(.pink))
                            }
                            context.fill(Path(CGRect(x: time / duration * size.width, y: 0, width: 2, height: size.height)), with: .color(.white))
                        }.allowsHitTesting(false)
                    }.clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            time = min(duration - 0.001, max(0, value.location.x / max(1, geometry.size.width) * duration))
                        }.onEnded { _ in onSeek() })
                }.frame(height: 56).accessibilityHidden(true)
                if !data.waveform.isEmpty {
                    Canvas { context, size in
                        for (i, level) in data.waveform.enumerated() {
                            let height = max(2, Double(level) * size.height)
                            context.fill(Path(CGRect(x: Double(i) / 96 * size.width, y: (size.height - height) / 2,
                                width: max(1, size.width / 96 - 1), height: height)), with: .color(.secondary))
                        }
                        for range in edits.silencedRanges {
                            context.fill(Path(CGRect(x: range.start / duration * size.width, y: 0,
                                width: (range.end - range.start) / duration * size.width, height: size.height)), with: .color(.blue.opacity(0.45)))
                        }
                    }.frame(height: 34).accessibilityLabel("Audio waveform. \(edits.silencedRanges.count) muted sections.")
                }
            } else if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            else { ProgressView("Loading timeline…") }
            LabeledContent("Playhead", value: Self.label(time))
            Slider(value: $time, in: 0...max(0.001, duration - 0.001), onEditingChanged: { if !$0 { onSeek() } })
                .accessibilityLabel("Timeline playhead").accessibilityValue(Self.label(time))
            HStack {
                Button("Previous Frame", systemImage: "backward.end") { seek(time - 1 / (data?.frameRate ?? 30)) }
                Spacer()
                Button("Next Frame", systemImage: "forward.end") { seek(time + 1 / (data?.frameRate ?? 30)) }
            }.labelStyle(.iconOnly).controlSize(.large)
            HStack {
                Button("Start Trim Here") { edits.trimStart = min(max(0, time), (edits.trimEnd ?? duration) - 0.1) }
                Spacer()
                Button("End Trim Here") { edits.trimEnd = max(edits.trimStart + 0.1, min(duration, time)) }
            }.font(.subheadline)
            if !keys.isEmpty {
                HStack {
                    Button("Previous Keyframe") { if let previous = keys.last(where: { $0.time < time - 0.001 }) { seek(previous.time) } }
                    Spacer()
                    Button("Next Keyframe") { if let next = keys.first(where: { $0.time > time + 0.001 }) { seek(next.time) } }
                }.font(.subheadline)
            }
            Text("Pink lines mark the selected blur’s keyframes. Blue waveform bands mark muted audio. Dimmed frames are outside the trim.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: asset.id) {
            do { let loaded = try await model.timeline(for: asset); if !Task.isCancelled { data = loaded } }
            catch { if !Task.isCancelled { self.error = "Timeline preview unavailable. You can still adjust the times below." } }
        }
        .onChange(of: model.privateGeneration) { _, _ in data = nil }
        .onDisappear { data = nil }
    }
    private func seek(_ value: Double) { time = min(duration - 0.001, max(0, value)); onSeek() }
    static func label(_ value: Double) -> String { String(format: "%02d:%06.3f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60)) }
}
