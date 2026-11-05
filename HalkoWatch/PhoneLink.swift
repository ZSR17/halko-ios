import Foundation
import HalkoCore
import os
import SwiftData
import WatchConnectivity

// The watch's side of the link with the iPhone app: keeps the workouts it sends and the pictures of their exercises,
// and the two apps give each other the sessions done. The watch never waits on it: the iPhone may be away, and what
// each one sends arrives once it is back.
final class PhoneLink: NSObject {
    nonisolated private static let logger = Logger(subsystem: "com.zsr.halko", category: "phone")
    // A plan came from the iPhone: until then, the watch asks for it at each launch.
    private static let planReceivedKey = "planReceived"
    // The sessions changed after this date are still to hand over.
    private static let sessionsCursorKey = "sessionsSentUntil"
    // The files being sent, removed once delivered.
    private static let outbox = URL.cachesDirectory.appending(path: "PhoneOutbox", directoryHint: .isDirectory)

    private let container: ModelContainer
    private let thumbnails: Thumbnails
    private let defaults = UserDefaults.standard
    // Asked for since launch; asked for again at the next one if they have not come.
    private var askedThumbnails: Set<String> = []
    private var pendingSessions: Task<Void, Never>?

    init(container: ModelContainer, thumbnails: Thumbnails) {
        self.container = container
        self.thumbnails = thumbnails
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // A session finished, among other changes: handed over once the changes are over.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.databaseChanged()
            }
        }
    }

    private func databaseChanged() {
        pendingSessions?.cancel()
        pendingSessions = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            sendSessions()
        }
    }

    // Delivered even later, with either app closed; what could not be sent goes at the next launch.
    private func sendSessions() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        do {
            let since = defaults.object(forKey: Self.sessionsCursorKey) as? Date ?? .distantPast
            guard let changes = try container.mainContext.sessionChanges(since: since, items: true) else { return }
            try FileManager.default.createDirectory(at: Self.outbox, withIntermediateDirectories: true)
            let file = Self.outbox.appending(path: "sessions-\(UUID().uuidString).json")
            try changes.encoded().write(to: file)
            session.transferFile(file, metadata: [CompanionMessage.kindKey: CompanionMessage.sessionsKind])
            defaults.set(changes.cursor, forKey: Self.sessionsCursorKey)
        } catch {
            Self.logger.error("Cannot send the sessions to the iPhone: \(String(describing: error))")
        }
    }

    // What the iPhone has now need not go back to it, once what was waiting here is on its way.
    private func received(_ changes: SessionChanges) async {
        sendSessions()
        do {
            try await Self.keep(changes, in: container)
            let since = defaults.object(forKey: Self.sessionsCursorKey) as? Date ?? .distantPast
            defaults.set(max(since, changes.cursor), forKey: Self.sessionsCursorKey)
        } catch {
            Self.logger.error("Cannot keep the sessions of the iPhone: \(String(describing: error))")
        }
    }

    // The whole history can come at once: away from the session on screen.
    @concurrent
    nonisolated private static func keep(_ changes: SessionChanges, in container: ModelContainer) async throws {
        try ModelContext(container).apply(changes)
    }

    private func linked() {
        let session = WCSession.default
        if !defaults.bool(forKey: Self.planReceivedKey) && !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[CompanionMessage.planRequestKey] != nil }) {
            session.transferUserInfo([CompanionMessage.planRequestKey: true])
        }
        askForThumbnails()
        sendSessions()
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
            case CompanionMessage.sessionsKind:
                let changes = try SessionChanges(decoding: Data(contentsOf: file.fileURL))
                Task { @MainActor in
                    await self.received(changes)
                }
            default:
                break
            }
        } catch {
            Self.logger.error("Cannot read a file from the iPhone: \(String(describing: error))")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard let error else { return }
        Self.logger.error("A file did not reach the iPhone: \(String(describing: error))")
        // Sent again: a row arriving twice changes nothing.
        Task { @MainActor in
            self.defaults.removeObject(forKey: Self.sessionsCursorKey)
        }
    }
}
