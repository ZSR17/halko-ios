import SwiftUI
import UIKit

// A duration in the workout editor (a rest, the time of a set, the pause to change sides): a box that opens two
// wheels instead of the keyboard. What the wheels show is applied at once, the box framed while they are open.
struct DurationField: View {
    let label: Text
    let value: Double?
    // What the wheels are for: "Rest", over "Set 1 · Bench press".
    let title: String
    let subtitle: String
    let format: (Double?) -> String
    let focus: FocusState<EditorField?>.Binding
    // When the wheels open, before anything is changed.
    let begin: () -> Void
    let commit: (Double?) -> Void
    @State private var choosing = false
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        let seconds = Int((value ?? 0).rounded())
        Button {
            focus.wrappedValue = nil
            begin()
            choosing = true
        } label: {
            Text(verbatim: value == nil ? "–" : format(value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Color(.secondaryText) : .primary)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: max(44, height))
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.tint, lineWidth: 2)
                        .opacity(choosing ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: DurationWheels.spoken(seconds)))
        .sheet(isPresented: $choosing) {
            DurationPicker(title: title, subtitle: subtitle, seconds: seconds) { seconds in
                commit(Double(seconds))
            }
        }
    }
}

// The sheet of the wheels: what they are for, minutes and seconds, and Validate where the session has Validate the set.
private struct DurationPicker: View {
    let title: String
    let subtitle: String
    let seconds: Int
    let change: (Int) -> Void
    @State private var contentHeight: CGFloat = 320
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            DurationWheels(seconds: seconds, change: change)
                .frame(height: 216)
            Button {
                dismiss()
            } label: {
                Text("Validate")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        // Below the grabber.
        .padding(.top, 22)
        .padding(.horizontal)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            contentHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Validate goes down into the area of the home indicator, 20 points above the edge of the screen, as the
        // session's Validate the set.
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(contentHeight + 20)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.secondarySystemGroupedBackground))
    }
}

// Minutes from 0 to 60 and seconds from 0 to 59, each wheel going round: after the last value comes the first. Their
// units stay beside the values chosen.
struct DurationWheels: UIViewRepresentable {
    let seconds: Int
    let change: (Int) -> Void

    // "2 minutes, 30 seconds", as VoiceOver reads a duration.
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    func makeUIView(context: Context) -> WheelsView {
        let view = WheelsView()
        view.change = change
        view.show(seconds)
        return view
    }

    func updateUIView(_ view: WheelsView, context: Context) {
        view.change = change
    }

    final class WheelsView: UIView, UIPickerViewDataSource, UIPickerViewDelegate {
        var change: (Int) -> Void = { _ in }

        // Each wheel holds its values that many times over and is brought back to the middle once it stops: it seems
        // to go round without an end.
        private static let rounds = 200
        private static let counts = [61, 60]
        private static let units: [UnitDuration] = [.minutes, .seconds]

        private let picker = UIPickerView()
        private let unitLabels = units.map { unit in
            let label = UILabel()
            let formatter = MeasurementFormatter()
            formatter.unitStyle = .short
            label.text = formatter.string(from: unit)
            label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
            label.adjustsFontForContentSizeCategory = true
            label.isAccessibilityElement = false
            return label
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            picker.dataSource = self
            picker.delegate = self
            picker.translatesAutoresizingMaskIntoConstraints = false
            addSubview(picker)
            NSLayoutConstraint.activate([
                picker.leadingAnchor.constraint(equalTo: leadingAnchor),
                picker.trailingAnchor.constraint(equalTo: trailingAnchor),
                picker.topAnchor.constraint(equalTo: topAnchor),
                picker.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            for label in unitLabels {
                addSubview(label)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        func show(_ seconds: Int) {
            let values = [min(seconds / 60, 60), seconds % 60]
            for component in values.indices {
                picker.selectRow(Self.middle(component) + values[component], inComponent: component, animated: false)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Each unit just after the value chosen, on its row.
            for component in unitLabels.indices {
                let label = unitLabels[component]
                guard let row = picker.view(forRow: picker.selectedRow(inComponent: component), forComponent: component) else {
                    // Its rows are laid out after the first pass.
                    guard window != nil else { continue }
                    Task { @MainActor [weak self] in
                        self?.setNeedsLayout()
                    }
                    continue
                }
                let frame = row.convert(row.bounds, to: self)
                let size = label.intrinsicContentSize
                label.frame = CGRect(x: frame.maxX - unitWidth, y: picker.frame.midY - size.height / 2, width: unitWidth, height: size.height)
            }
        }

        private static func middle(_ component: Int) -> Int {
            rounds / 2 * counts[component]
        }

        private var numberFont: UIFont {
            UIFontMetrics(forTextStyle: .title2).scaledFont(for: .monospacedDigitSystemFont(ofSize: 22, weight: .regular))
        }

        private var numberWidth: CGFloat {
            ceil(("00" as NSString).size(withAttributes: [.font: numberFont]).width) + 4
        }

        private var unitWidth: CGFloat {
            ceil(unitLabels.map(\.intrinsicContentSize.width).max() ?? 0) + 10
        }

        // MARK: UIPickerViewDataSource, UIPickerViewDelegate

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            Self.counts.count
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            Self.rounds * Self.counts[component]
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            numberWidth + unitWidth
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            max(36, ceil(numberFont.lineHeight) + 10)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let value = row % Self.counts[component]
            let label = view as? UILabel ?? UILabel()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            // The room of the unit, on the right.
            paragraph.tailIndent = -unitWidth
            label.attributedText = NSAttributedString(
                string: value.formatted(),
                attributes: [.font: numberFont, .paragraphStyle: paragraph, .foregroundColor: UIColor.label]
            )
            label.accessibilityLabel = Measurement(value: Double(value), unit: Self.units[component]).formatted(.measurement(width: .wide))
            return label
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            let formatter = MeasurementFormatter()
            formatter.unitStyle = .long
            return formatter.string(from: Self.units[component]).localizedCapitalized
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let values = Self.counts.indices.map { pickerView.selectedRow(inComponent: $0) % Self.counts[$0] }
            // Back to the middle, on the same value.
            pickerView.selectRow(Self.middle(component) + values[component], inComponent: component, animated: false)
            change(values[0] * 60 + values[1])
        }
    }
}
