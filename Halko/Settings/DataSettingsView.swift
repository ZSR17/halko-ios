import HalkoCore
import OSLog
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// What the iPhone holds of the user's, a file to keep it or take it elsewhere, a file added back, and everything erased.
// What changes here reaches the watch with the next save.
struct DataSettingsView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "data")

    @Environment(\.modelContext) private var context
    @AppStorage(PlateSettings.storageKey) private var plates = Data()
    @State private var counts: DataCounts?
    @State private var size: Int64?
    // A session not finished yet, which erasing would leave behind.
    @State private var inProgress = false
    @State private var exported: ExportedFile?
    @State private var importing = false
    @State private var imported: ImportResult?
    @State private var unreadable = false
    @State private var erasing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Sessions done") {
                    count(\.sessions)
                }
                LabeledContent("Planned workouts") {
                    count(\.workouts)
                }
                LabeledContent("My exercises") {
                    count(\.exercises)
                }
                LabeledContent("Size") {
                    Text(verbatim: size.map { $0.formatted(.byteCount(style: .file)) } ?? "")
                }
            } header: {
                // In a darker grey than the system's, for a contrast of 4.5:1.
                Text("On this iPhone")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Button("Export", action: export)
                Button("Import") {
                    importing = true
                }
            } header: {
                Text("File")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Export makes a Halko file with everything (sessions, workouts, exercises, plates), to keep in Files or to send. Import adds it to what is here: nothing is erased, and a session is never there twice.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Button(role: .destructive) {
                    erasing = true
                } label: {
                    // In a darker red than the system's on light, lighter on dark, for a contrast of 4.5:1.
                    Text("Erase all")
                        .foregroundStyle(inProgress ? Color(.secondaryText) : Color(.destructiveText))
                        .frame(maxWidth: .infinity)
                }
                .disabled(inProgress)
                // Shown from the button.
                .confirmationDialog("Erase everything on this iPhone and on the watch?", isPresented: $erasing, titleVisibility: .visible) {
                    Button("Export first", action: export)
                    Button("Erase all", role: .destructive, action: eraseAll)
                } message: {
                    Text("Sessions, workouts, your exercises and plates. Export first to keep a copy.")
                }
            } footer: {
                if inProgress {
                    Text("Finish the session in progress to erase everything.")
                        .foregroundStyle(Color(.secondaryText))
                }
            }
        }
        .navigationTitle("My data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
        }
        .sheet(item: $exported) { file in
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                load(url)
            }
        }
        .alert("Imported", isPresented: Binding { imported != nil } set: { if !$0 { imported = nil } }, presenting: imported) { _ in
        } message: { result in
            Text(verbatim: [
                String(localized: "Sessions: \(result.sessions.added) added, \(result.sessions.alreadyThere) already there."),
                String(localized: "Workouts: \(result.workouts.added) added, \(result.workouts.alreadyThere) already there."),
                String(localized: "Custom exercises: \(result.exercises.added) added, \(result.exercises.alreadyThere) already there."),
            ].joined(separator: "
"))
        }
        .alert("This file can't be read", isPresented: $unreadable) {
        } message: {
            Text("It isn't a Halko file, or it comes from a later version of Halko.")
        }
    }

    private func count(_ figure: KeyPath<DataCounts, Int>) -> Text {
        Text(verbatim: counts.map { $0[keyPath: figure].formatted() } ?? "")
    }

    private func refresh() {
        counts = try? context.dataCounts()
        inProgress = ((try? context.fetchCount(FetchDescriptor<Session>(predicate: #Predicate { !$0.removed && $0.endedAt == nil }))) ?? 0) > 0
        // The database with its journal.
        if let url = context.container.configurations.first?.url {
            size = ["", "-wal", "-shm"]
                .compactMap { try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false) + $0)[.size] as? Int64 }
                .reduce(0, +)
        }
    }

    private func export() {
        do {
            let backup = try context.backup(plates: try? JSONDecoder().decode(PlateSettings.self, from: plates))
            let name = "Halko \(Date.now.formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appending(path: name)
            try backup.encoded().write(to: url, options: .atomic)
            exported = ExportedFile(url: url)
        } catch {
            Self.logger.error("Cannot export: \(String(describing: error))")
        }
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let backup = try Backup(decoding: Data(contentsOf: url))
            imported = try context.restore(backup)
            // The plates only where there are none: nothing here is replaced.
            if let file = backup.plates, (try? JSONDecoder().decode(PlateSettings.self, from: plates))?.plates.isEmpty ?? true {
                plates = try JSONEncoder().encode(file)
            }
        } catch {
            Self.logger.error("Cannot import: \(String(describing: error))")
            unreadable = true
        }
        refresh()
    }

    private func eraseAll() {
        do {
            try context.eraseAll()
            plates = Data()
        } catch {
            Self.logger.error("Cannot erase: \(String(describing: error))")
        }
        refresh()
    }
}

private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

// The system's sheet to share a file or save it in Files.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
