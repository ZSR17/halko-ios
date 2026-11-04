import CryptoKit
import Foundation
import HalkoCore
import os
import SwiftData
import UIKit
import WatchConnectivity

// The iPhone's side of the link with the watch app: hands it the workouts to do as they change, and the pictures of
// their exercises it asks for. Nothing waits on it: WatchConnectivity delivers them when the watch is there, even
// later, with either app closed.
final class WatchLink: NSObject {
    nonisolated private static let logger = Logger(subsystem: "com.zsr.halko", category: "watch")
    // The plan last handed to the watch: only a changed one is sent.
    private static let sentPlanKey = "watchPlanDigest"
    // The files being sent, removed once delivered.
    private static let outbox = URL.cachesDirectory.appending(path: "WatchOutbox", directoryHint: .isDirectory)
    // The shorter side of a picture sent, in pixels: a thumbnail of the watch's page of a workout, sharp at 3x.
    private static let thumbnailPixels = 150.0

    private let container: ModelContainer
    private let defaults = UserDefaults.standard
    private var pendingPlan: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // Any change of the database, the workouts' among others: sent once the changes are over.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.planChanged()
            }
        }
    }

    private func planChanged() {
        pendingPlan?.cancel()
        pendingPlan = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            sendPlan()
        }
    }

    // `again`: even when the watch had this plan, since it asks for it.
    private func sendPlan(again: Bool = false) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let plan = try container.mainContext.planSnapshot().encoded()
            let digest = SHA256.hash(data: plan).map { String(format: "%02x", $0) }.joined()
            guard again || defaults.string(forKey: Self.sentPlanKey) != digest else { return }
            // Only the last plan is worth delivering.
            for transfer in session.outstandingFileTransfers where transfer.file.metadata?[CompanionMessage.kindKey] as? String == CompanionMessage.planKind {
                transfer.cancel()
                try? FileManager.default.removeItem(at: transfer.file.fileURL)
            }
            let file = try Self.write(plan, named: "plan-\(UUID().uuidString).json")
            session.transferFile(file, metadata: [CompanionMessage.kindKey: CompanionMessage.planKind])
            defaults.set(digest, forKey: Self.sentPlanKey)
        } catch {
            Self.logger.error("Cannot send the workouts to the watch: \(String(describing: error))")
        }
    }

    private func sendThumbnails(_ mediaIDs: [String]) {
        let session = WCSession.default
        let sending = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?[CompanionMessage.mediaIDKey] as? String })
        for mediaID in Set(mediaIDs).subtracting(sending) {
            guard let thumbnail = Self.thumbnail(mediaID) else { continue }
            do {
                let file = try Self.write(thumbnail, named: "\(UUID().uuidString).jpg")
                session.transferFile(file, metadata: [
                    CompanionMessage.kindKey: CompanionMessage.thumbnailKind,
                    CompanionMessage.mediaIDKey: mediaID,
                ])
            } catch {
                Self.logger.error("Cannot send a picture to the watch: \(String(describing: error))")
            }
        }
    }

    // The picture made small enough to fill the thumbnail, as JPEG.
    private static func thumbnail(_ mediaID: String) -> Data? {
        guard let picture = ExerciseMedia.image(mediaID) else { return nil }
        let scale = min(1, thumbnailPixels / min(picture.size.width, picture.size.height))
        let size = CGSize(width: (picture.size.width * scale).rounded(), height: (picture.size.height * scale).rounded())
        return (picture.preparingThumbnail(of: size) ?? picture).jpegData(compressionQuality: 0.8)
    }

    private static func write(_ data: Data, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let file = outbox.appending(path: name)
        try data.write(to: file)
        return file
    }
}

// Called on a background queue.
extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Self.logger.error("Cannot reach the watch: \(String(describing: error))")
        }
        Task { @MainActor in
            self.sendPlan()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    // Another watch was chosen: the link goes to it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    // The watch app installed, or removed: a watch app installed again gets the plan.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            if !WCSession.default.isWatchAppInstalled {
                self.defaults.removeObject(forKey: Self.sentPlanKey)
            }
            self.sendPlan()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let plan = userInfo[CompanionMessage.planRequestKey] != nil
        let thumbnails = userInfo[CompanionMessage.thumbnailsKey] as? [String] ?? []
        Task { @MainActor in
            if plan {
                self.sendPlan(again: true)
            }
            self.sendThumbnails(thumbnails)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard let error else { return }
        Self.logger.error("A file did not reach the watch: \(String(describing: error))")
        // Sent again at the next change, or when the watch asks for it.
        if fileTransfer.file.metadata?[CompanionMessage.kindKey] as? String == CompanionMessage.planKind {
            Task { @MainActor in
                self.defaults.removeObject(forKey: Self.sentPlanKey)
            }
        }
    }
}
