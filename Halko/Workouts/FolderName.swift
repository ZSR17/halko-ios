import SwiftUI

extension View {
    // The name of a folder asked in an alert: `name` to start from, `save` given it without the spaces around, never
    // empty.
    func folderNameAlert(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        action: LocalizedStringKey,
        name: String = "",
        message: LocalizedStringKey? = nil,
        save: @escaping (String) -> Void
    ) -> some View {
        modifier(FolderNameAlert(title: title, isPresented: isPresented, action: action, name: name, message: message, save: save))
    }
}

private struct FolderNameAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var isPresented: Bool
    let action: LocalizedStringKey
    let name: String
    let message: LocalizedStringKey?
    let save: (String) -> Void
    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            // Its buttons in the color of a text, as every alert's.
            .background {
                Color.clear
                    .alert(title, isPresented: $isPresented) {
                        TextField("Name", text: $text)
                        Button("Cancel", role: .cancel) {}
                        Button(action) {
                            save(trimmed)
                        }
                        .disabled(trimmed.isEmpty)
                    } message: {
                        if let message {
                            Text(message)
                        }
                    }
                    .tint(.primary)
            }
            .onChange(of: isPresented) { _, shown in
                if shown {
                    text = name
                }
            }
    }
}
