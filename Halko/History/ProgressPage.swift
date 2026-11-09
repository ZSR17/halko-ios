import Charts
import HalkoCore
import SwiftData
import SwiftUI

// The progress of an exercise: chosen among those done, the last one done first; a measure that counts for its type; its
// curve over a period, which is remembered; and the sessions of that period, each one opening.
struct ProgressPage: View {
    // Listed under the chart before « See the … others ».
    private static let listed = 5

    let history: SessionHistory
    let text: HistoryText
    @AppStorage("progressPeriod") private var period = ProgressPeriod.threeMonths
    @State private var exerciseID: String?
    @State private var chosenMeasure: ProgressMeasure?
    @State private var showsAll = false

    var body: some View {
        if let exercise = history.exercises.first(where: { $0.id == exerciseID }) ?? history.exercises.first {
            content(exercise)
        } else {
            Text("Do a session to track your progress.")
                .foregroundStyle(Color(.secondaryText))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private func content(_ exercise: Exercise) -> some View {
        let measures = ProgressMeasure.measures(for: exercise.exerciseType)
        let measure = chosenMeasure.flatMap { measures.contains($0) ? $0 : nil } ?? measures[0]
        let progress = history.progress(of: exercise, measure: measure)
        let shown = progress.points(in: period, now: .now, calendar: .current)
        return VStack(alignment: .leading, spacing: 10) {
            exerciseMenu(exercise)
            VStack(alignment: .leading, spacing: 6) {
                measureMenu(measures, chosen: measure)
                headline(progress)
                if shown.count >= 2 {
                    ProgressChart(points: shown, measure: measure, text: text)
                        .frame(height: 150)
                } else {
                    (progress.points.count < 2 ? Text("It takes 2 sessions to draw the curve.") : Text("Fewer than 2 sessions in this period: choose a longer one."))
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
                Picker("Period", selection: $period) {
                    ForEach(ProgressPeriod.allCases, id: \.self) { period in
                        Text(period.name)
                            .tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            }
            .sessionCard()
            if !shown.isEmpty {
                sessions(shown, measure: measure)
            }
        }
        .onChange(of: period) {
            showsAll = false
        }
    }

    private func exerciseMenu(_ exercise: Exercise) -> some View {
        Menu {
            Picker("Exercise", selection: Binding {
                exercise.id
            } set: { id in
                exerciseID = id
                showsAll = false
            }) {
                ForEach(history.exercises) { exercise in
                    Text(verbatim: exercise.localizedName)
                        .tag(exercise.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            menuLabel(Text(verbatim: exercise.localizedName).font(.headline))
        }
        .accessibilityLabel(Text("Exercise"))
        .accessibilityValue(Text(verbatim: exercise.localizedName))
    }

    @ViewBuilder
    private func measureMenu(_ measures: [ProgressMeasure], chosen: ProgressMeasure) -> some View {
        if measures.count > 1 {
            Menu {
                Picker("Measure", selection: Binding {
                    chosen
                } set: { measure in
                    chosenMeasure = measure
                }) {
                    ForEach(measures, id: \.self) { measure in
                        Text(measure.name)
                            .tag(measure)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                menuLabel(Text(chosen.name).font(.subheadline.weight(.semibold)))
            }
            .accessibilityLabel(Text("Measure"))
            .accessibilityValue(Text(chosen.name))
        } else {
            Text(chosen.name)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
    }

    private func menuLabel(_ title: some View) -> some View {
        HStack(spacing: 6) {
            title
                .foregroundStyle(Color(.label))
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryText))
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    // The record and the day it was reached; for an estimate, which is not a record, the latest one.
    @ViewBuilder
    private func headline(_ progress: ExerciseProgress) -> some View {
        if let point = progress.measure.isRecord ? progress.best : progress.points.last {
            let day = point.date.formatted(.dateTime.day().month(.abbreviated))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: text.value(point.value, of: progress.measure))
                    .font(.title2.bold())
                    .monospacedDigit()
                Spacer()
                if progress.measure.isRecord {
                    Text("record · \(day)")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                } else {
                    Text(verbatim: day)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // The latest first.
    private func sessions(_ points: [ProgressPoint], measure: ProgressMeasure) -> some View {
        let latest = Array(points.reversed())
        let listed = showsAll ? latest : Array(latest.prefix(Self.listed))
        return VStack(spacing: 0) {
            ForEach(listed) { point in
                NavigationLink(value: PastSessionLink(sessionID: point.id)) {
                    HStack {
                        Text(verbatim: point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .foregroundStyle(Color(.secondaryText))
                        Spacer()
                        Text(verbatim: text.value(point.value, of: measure))
                            .bold()
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if point.id != listed.last?.id {
                    Divider()
                }
            }
            if latest.count > Self.listed {
                Divider()
                Button {
                    showsAll.toggle()
                } label: {
                    Group {
                        if showsAll {
                            Text("Show less")
                        } else if latest.count - Self.listed == 1 {
                            Text("See the other one")
                        } else {
                            Text("See the \(latest.count - Self.listed) others")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

// The curve of a measure, the oldest session on the left, with a dot on the latest one.
private struct ProgressChart: View {
    let points: [ProgressPoint]
    let measure: ProgressMeasure
    let text: HistoryText

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Measure", text.plotted(point.value, of: measure))
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .accessibilityLabel(Text(verbatim: point.date.formatted(.dateTime.day().month(.wide).year())))
                .accessibilityValue(Text(verbatim: text.value(point.value, of: measure)))
            }
            if let last = points.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Measure", text.plotted(last.value, of: measure))
                )
                .symbolSize(70)
                .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        // Room for the last date and the dot, at the end of the axis.
        .chartXScale(range: .plotDimension(endPadding: 24))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let plotted = value.as(Double.self) {
                        Text(verbatim: text.axis(plotted, of: measure))
                            .foregroundStyle(Color(.secondaryText))
                    }
                }
            }
        }
    }
}
