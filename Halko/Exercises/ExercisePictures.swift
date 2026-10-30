import SwiftUI
import UIKit

// The pictures of an exercise, its start and end positions: shown in turn, as a loop of the movement, or side by
// side when motion is reduced. A picture only: the steps say the movement in words.
struct ExercisePictures: View {
    let mediaIDs: [String]
    @State private var pictures: [UIImage] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color(.tertiarySystemFill)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                content
            }
            .clipShape(.rect(cornerRadius: 18))
            .accessibilityHidden(true)
            .task(id: mediaIDs) {
                var loaded: [UIImage] = []
                for mediaID in mediaIDs {
                    guard let picture = UIImage.exercise(mediaID) else { continue }
                    loaded.append(await picture.byPreparingForDisplay() ?? picture)
                }
                pictures = loaded
            }
    }

    @ViewBuilder private var content: some View {
        if pictures.isEmpty {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(Color(.secondaryText))
        } else if reduceMotion || pictures.count == 1 {
            HStack(spacing: 2) {
                ForEach(pictures, id: \.self) { picture in
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let shown = pictures[Int(context.date.timeIntervalSinceReferenceDate) % pictures.count]
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 6) {
                            ForEach(pictures, id: \.self) { picture in
                                Circle()
                                    .fill(picture == shown ? Color.accentColor : Color(.secondaryText))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(10)
                    }
            }
        }
    }
}
