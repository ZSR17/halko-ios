import SwiftUI

// A log kept on the iPhone, newest first, to read and pass on: of the sound of the end of the rests, of the workout of
// Health on the watch.
struct LogView<Empty: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let clear: () -> Void
    let empty: Empty
    @AppStorage private var log: String

    init(key: String, title: LocalizedStringKey, icon: String, clear: @escaping () -> Void, @ViewBuilder empty: () -> Empty) {
        _log = AppStorage(wrappedValue: "", key)
        self.title = title
        self.icon = icon
        self.clear = clear
        self.empty = empty()
    }

    var body: some View {
        ScrollView {
            Text(verbatim: log.split(separator: "
").reversed().joined(separator: "
"))
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .overlay {
            if log.isEmpty {
                ContentUnavailableView {
                    Label("Nothing yet", systemImage: icon)
                } description: {
                    empty
                        .foregroundStyle(Color(.secondaryText))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: log)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Clear", role: .destructive, action: clear)
                }
            }
        }
    }
}
