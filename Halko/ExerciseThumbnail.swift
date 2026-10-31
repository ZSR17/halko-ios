import SwiftUI
import UIKit

// The first picture of an exercise, small: from the embedded library or picked by the user (`ExerciseMedia`). An
// exercise without one shows a dumbbell.
struct ExerciseThumbnail: View {
    let mediaID: String?
    @ScaledMetric private var side: Double
    // Grows with the text, up to a size that leaves room for it.
    private let largestSide: Double
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(mediaID: String?, side: Double = 56) {
        self.mediaID = mediaID
        _side = ScaledMetric(wrappedValue: side, relativeTo: .headline)
        largestSide = side * 12 / 7
    }

    var body: some View {
        let size = min(side, largestSide)
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
            guard let mediaID, let picture = ExerciseMedia.image(mediaID) else { return }
            // Filling the square, at the pixels of the screen.
            let scale = size * displayScale / min(picture.size.width, picture.size.height)
            image = await picture.byPreparingThumbnail(ofSize: CGSize(width: picture.size.width * scale, height: picture.size.height * scale))
        }
    }
}
