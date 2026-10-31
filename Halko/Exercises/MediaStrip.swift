import os
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// The pictures and video of an exercise being edited, in a row: picked in Photos, which shares only those chosen,
// and kept on the device. The first is the thumbnail; touched and held, one moves to another place.
struct MediaStrip: View {
    @Binding var mediaIDs: [String]
    // A media picked: its files go again if the exercise does not keep it.
    let imported: (String) -> Void
    @State private var picked: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var failed = false
    @ScaledMetric(relativeTo: .body) private var tileSide = 104.0

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "media")

    var body: some View {
        let side = min(tileSide, 160)
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(mediaIDs, id: \.self) { id in
                    tile(id, side: side)
                }
                if isImporting {
                    ProgressView()
                        .frame(width: side, height: side)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                }
                PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos])) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                        Text("Photo or video")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(6)
                    .frame(width: side, height: side)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isImporting)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .task(id: picked) {
            guard !picked.isEmpty else { return }
            isImporting = true
            for item in picked {
                do {
                    let id = try await importMedia(item)
                    imported(id)
                    mediaIDs.append(id)
                } catch {
                    Self.logger.error("Cannot add a photo or video: \(String(describing: error))")
                    failed = true
                }
            }
            isImporting = false
            picked = []
        }
        .alert("This photo or video could not be added.", isPresented: $failed) {
            Button("OK") {}
        }
    }

    private func importMedia(_ item: PhotosPickerItem) async throws -> String {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else { throw CocoaError(.fileReadNoSuchFile) }
            return try await ExerciseMedia.importVideo(video.url)
        }
        guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadNoSuchFile) }
        return try await ExerciseMedia.importPhoto(data)
    }

    private func tile(_ id: String, side: CGFloat) -> some View {
        let index = mediaIDs.firstIndex(of: id) ?? 0
        let isVideo = ExerciseMedia.video(id) != nil
        return ExerciseThumbnail(mediaID: id, side: side)
            .overlay(alignment: .bottomLeading) {
                caption(index: index, isVideo: isVideo)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    remove(id)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.7), in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
            .draggable(id) {
                ExerciseThumbnail(mediaID: id, side: 64)
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let moved = ids.first, mediaIDs.contains(moved) else { return }
                move(moved, to: index)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isVideo ? Text("Video \(index + 1)") : Text("Photo \(index + 1)"))
            .accessibilityAction(named: "Remove") {
                remove(id)
            }
            .accessibilityAction(named: "Move left") {
                move(id, to: max(index - 1, 0))
            }
            .accessibilityAction(named: "Move right") {
                move(id, to: min(index + 1, mediaIDs.count - 1))
            }
    }

    // "Start" and "End" on the two pictures of a movement, as the library has them; a video says it is one.
    @ViewBuilder private func caption(index: Int, isVideo: Bool) -> some View {
        let label: Text? = if isVideo {
            Text(Image(systemName: "play.fill"))
        } else if mediaIDs.count == 2 {
            index == 0 ? Text("Beginning") : Text("End")
        } else {
            nil
        }
        if let label {
            label
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7), in: .capsule)
                .padding(6)
        }
    }

    private func remove(_ id: String) {
        mediaIDs.removeAll { $0 == id }
    }

    private func move(_ id: String, to index: Int) {
        guard let from = mediaIDs.firstIndex(of: id), from != index else { return }
        mediaIDs.remove(at: from)
        mediaIDs.insert(id, at: index)
    }
}
