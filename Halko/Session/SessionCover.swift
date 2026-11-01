import HalkoCore
import SwiftData
import SwiftUI

// The session in full screen, without the rest of the app: the session in progress, then its summary once saved.
struct SessionCover: View {
    @Environment(LiveSessionStore.self) private var store
    @State private var finished: Session?

    var body: some View {
        if let finished {
            SessionSummaryView(session: finished)
        } else if let state = store.state {
            LiveSessionView(state: state) { session in
                finished = session
            }
        }
    }
}

extension LiveSessionStore {
    // Shows a session in progress: the one on this device as it was left, else one started elsewhere from its sets.
    func open(_ session: Session, in context: ModelContext) throws {
        if state?.sessionID != session.id {
            set(try context.resumedState(of: session))
        }
        isPresented = true
    }
}
