import SwiftUI
import WidgetKit

// What Halko shows outside the app: the session in progress (Live Activity).
@main
struct HalkoWidgets: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}
