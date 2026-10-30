import SwiftUI
import UIKit

// The first picture of an exercise, small: from the pictures of the embedded library (`ExerciseImages/`), named
// by media id. An exercise without one there shows a dumbbell.
struct ExerciseThumbnail: View {
    let mediaID: String?
    @ScaledMetric(relativeTo: .headline) private var side = 56.0
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        // Grows with the text, up to a size that leaves room for it.
        let size = min(side, 96)
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "dumbbell")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: mediaID) {
            guard let mediaID, let picture = UIImage.exercise(mediaID) else { return }
            // Filling the square, at the pixels of the screen.
            let scale = size * displayScale / min(picture.size.width, picture.size.height)
            image = await picture.byPreparingThumbnail(ofSize: CGSize(width: picture.size.width * scale, height: picture.size.height * scale))
        }
    }
}

extension UIImage {
    // A picture of the embedded library, by media id.
    static func exercise(_ mediaID: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: mediaID, withExtension: "webp", subdirectory: "ExerciseImages") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
