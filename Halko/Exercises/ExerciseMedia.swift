import AVFoundation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

// The pictures and videos of the exercises, by media id: the embedded library's (`ExerciseImages/<id>.webp`), and
// the ones the user picks for their exercises, kept on the device (`Application Support/ExerciseMedia/`): `<id>.jpg`
// for a photo; for a video, the video with its first frame as `<id>.jpg`. Sending them to the server comes with the
// sync of the media.
nonisolated enum ExerciseMedia {
    private static let directory = URL.applicationSupportDirectory.appending(path: "ExerciseMedia", directoryHint: .isDirectory)
    private static let videoExtensions = ["mov", "mp4", "m4v"]
    // Large enough for the page of an exercise, on the largest screens.
    private static let largestSide = 1600.0

    // A photo, or the first frame of a video.
    static func image(_ id: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: id, withExtension: "webp", subdirectory: "ExerciseImages") {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(contentsOfFile: file(id, "jpg").path)
    }

    static func video(_ id: String) -> URL? {
        videoExtensions.lazy.map { file(id, $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // A photo picked in Photos, made smaller and kept as JPEG: its new media id.
    @concurrent static func importPhoto(_ data: Data) async throws -> String {
        guard let photo = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let id = newMediaID()
        try save(picture: photo, id: id)
        return id
    }

    // A video picked in Photos, moved here with its first frame: its new media id.
    @concurrent static func importVideo(_ url: URL) async throws -> String {
        let id = newMediaID()
        let pathExtension = url.pathExtension.lowercased()
        let video = file(id, videoExtensions.contains(pathExtension) ? pathExtension : "mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: video)
        do {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: largestSide, height: largestSide)
            let (frame, _) = try await generator.image(at: .zero)
            try save(picture: UIImage(cgImage: frame), id: id)
        } catch {
            try? FileManager.default.removeItem(at: video)
            throw error
        }
        return id
    }

    // The files of media the user picked; nothing for the library's.
    static func delete(_ ids: some Sequence<String>) {
        for id in ids {
            for pathExtension in ["jpg"] + videoExtensions {
                try? FileManager.default.removeItem(at: file(id, pathExtension))
            }
        }
    }

    private static func save(picture image: UIImage, id: String) throws {
        let scale = min(1, largestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let jpeg = (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: file(id, "jpg"), options: .atomic)
    }

    private static func file(_ id: String, _ pathExtension: String) -> URL {
        directory.appending(path: "\(id).\(pathExtension)")
    }

    private static func newMediaID() -> String {
        UUID().uuidString.lowercased()
    }
}

// A video picked in Photos, as a file of its own the app may move.
nonisolated struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}
