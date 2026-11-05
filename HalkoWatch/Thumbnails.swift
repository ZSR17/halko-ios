import Foundation
import SwiftUI
import UIKit

// The pictures of the exercises of the watch's workouts, sent small by the iPhone and kept on the watch
// (`Application Support/Thumbnails/<media id>.jpg`): the watch shows them without the iPhone.
@Observable
final class Thumbnails {
    nonisolated private static let directory = URL.applicationSupportDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)

    private(set) var stored: Set<String>

    init() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []
        stored = Set(files.map { ($0 as NSString).deletingPathExtension })
    }

    // A file received from the iPhone, moved here at once: the system deletes it after.
    nonisolated static func keep(_ file: URL, as mediaID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let kept = Self.file(mediaID)
        try? FileManager.default.removeItem(at: kept)
        try FileManager.default.moveItem(at: file, to: kept)
    }

    func received(_ mediaID: String) {
        stored.insert(mediaID)
    }

    func image(_ mediaID: String) -> UIImage? {
        stored.contains(mediaID) ? UIImage(contentsOfFile: Self.file(mediaID).path) : nil
    }

    nonisolated private static func file(_ mediaID: String) -> URL {
        directory.appending(path: "\(mediaID).jpg")
    }
}

// The first picture of an exercise, small; a dumbbell until the iPhone has sent it, or for an exercise without one.
struct ExerciseThumbnail: View {
    let mediaID: String?
    @Environment(Thumbnails.self) private var thumbnails
    @ScaledMetric(relativeTo: .headline) private var side = 36.0
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.fill.tertiary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "dumbbell")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
        // Read again once the iPhone has sent it.
        .task(id: mediaID.flatMap { thumbnails.stored.contains($0) ? $0 : nil }) {
            image = mediaID.flatMap(thumbnails.image)
        }
    }
}
