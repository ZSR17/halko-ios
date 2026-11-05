import Foundation
import HalkoCore
import os
import SwiftData
import WatchConnectivity

// The watch's side of the link with the iPhone app: keeps the workouts it sends and the pictures of their exercises.
// The watch never waits on it: the iPhone may be away, and what it sends arrives once it is back.
final class PhoneLink: NSObject {
    nonisolated private static let logger = Logger(subsystem: "com.zsr.halko", category: "phone")
    // A plan came from the iPhone: until then, the watch asks for it at each launch.
    private static let planReceivedKey = "planReceived"

    private let container: ModelContainer
    private let thumbnails: Thumbnails
    private let defaults = UserDefaults.standard
    // Asked for since launch; asked for again at the next one if they have not come.
    private var askedThumbnails: Set<String> = []

    init(container: ModelContainer, thumbnails: Thumbnails) {
        self.container = container
        self.thumbnails = thumbnails
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func linked() {
        let session = WCSession.default
        if !defaults.bool(forKey: Self.planReceivedKey) && !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[CompanionMessage.planRequestKey] != nil }) {
            session.transferUserInfo([CompanionMessage.planRequestKey: true])
        }
        askForThumbnails()
    }

    private func received(_ plan: PlanSnapshot) {
        do {
            try container.mainContext.apply(plan)
            defaults.set(true, forKey: Self.planReceivedKey)
        } catch {
            Self.logger.error("Cannot keep the workouts of the iPhone: \(String(describing: error))")
        }
        askForThumbnails()
    }

    // The pictures of the exercises of the workouts, which the watch lacks.
    private func askForThumbnails() {
        guard WCSession.default.activationState == .activated else { return }
        do {
            let missing = try container.mainContext.planMediaIDs().subtracting(thumbnails.stored).subtracting(askedThumbnails)
            guard !missing.isEmpty else { return }
            WCSession.default.transferUserInfo([CompanionMessage.thumbnailsKey: missing.sorted()])
            askedThumbnails.formUnion(missing)
        } catch {
            Self.logger.error("Cannot read the pictures the workouts need: \(String(describing: error))")
        }
    }
}

// Called on a background queue.
extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Self.logger.error("Cannot reach the iPhone: \(String(describing: error))")
        }
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.linked()
        }
    }

    // The file is deleted once this returns: read or moved before.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        do {
            switch metadata[CompanionMessage.kindKey] as? String {
            case CompanionMessage.planKind:
                let plan = try PlanSnapshot(decoding: Data(contentsOf: file.fileURL))
                Task { @MainActor in
                    self.received(plan)
                }
            case CompanionMessage.thumbnailKind:
                guard let mediaID = metadata[CompanionMessage.mediaIDKey] as? String else { return }
                try Thumbnails.keep(file.fileURL, as: mediaID)
                Task { @MainActor in
                    self.thumbnails.received(mediaID)
                }
            default:
                break
            }
        } catch {
            Self.logger.error("Cannot read a file from the iPhone: \(String(describing: error))")
        }
    }
}
