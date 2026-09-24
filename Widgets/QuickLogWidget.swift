import SwiftUI
import WidgetKit

private struct QuickLogEntry: TimelineEntry {
    let date: Date
    let snapshot: CalorieWidgetSnapshot?
}

private struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: .now, snapshot: CalorieWidgetSnapshot(day: .now, total: 500, goal: 2100))
    }
    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : QuickLogEntry(date: .now, snapshot: CalorieWidgetStorage.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let snapshot = CalorieWidgetStorage.read()
        completion(Timeline(entries: [QuickLogEntry(date: now, snapshot: snapshot), QuickLogEntry(date: midnight, snapshot: snapshot)], policy: .after(midnight)))
    }
}

private struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(spacing: 6) {
                    if let snapshot = entry.snapshot {
                        calorieSummary(snapshot, style: .caption)
                    }
                    GeometryReader { geometry in
                        let width = max(0, geometry.size.width - 8) / 2
                        let height = max(0, geometry.size.height - 8) / 2
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                actionLink(.barcode, width: width, height: height)
                                actionLink(.voice, width: width, height: height)
                            }
                            HStack(spacing: 8) {
                                actionLink(.image, width: width, height: height)
                                actionLink(.add, width: width, height: height)
                            }
                        }
                    }
                }
            } else {
                mediumContent
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = entry.snapshot {
                calorieSummary(snapshot, style: .headline)
            } else {
                Text("Cave Cals").font(.cave(.headline))
            }
            GeometryReader { geometry in
                let unitWidth = max(0, geometry.size.width - 24) / 4.4
                HStack(spacing: 8) {
                    ForEach(LoggingAction.allCases) { action in
                        actionLink(action, width: unitWidth * (action == .add ? 1.4 : 1), height: 56)
                    }
                }
            }.frame(height: 56)
        }
    }

    private func calorieSummary(_ snapshot: CalorieWidgetSnapshot, style: Font.TextStyle) -> some View {
        let total = snapshot.total(on: entry.date)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(total.formatted(.number.precision(.fractionLength(0))))
                .font(family == .systemSmall ? .cave(.subheadline).weight(.black) : .cave(style).bold())
                .foregroundStyle(.primary)
                .accessibilityLabel("Today: \(Int(total.rounded())) calories")
            Spacer(minLength: 0)
            if let goal = snapshot.goal, goal > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(abs(goal - total).formatted(.number.precision(.fractionLength(0))))
                        .foregroundStyle(.primary)
                    Text(total > goal ? "over" : "left")
                        .foregroundStyle(total > goal ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                }
                .font(.cave(style))
                .accessibilityElement(children: .combine)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, family == .systemSmall ? 8 : 0)
    }

    private func actionLink(_ action: LoggingAction, width: CGFloat, height: CGFloat) -> some View {
        Link(destination: action.url) {
            Group {
                if action == .add {
                    CaveSearchAddIcon(size: family == .systemSmall ? min(20, width / 3) : 22, compact: true)
                } else {
                    CaveIcon(action.caveGlyph, size: 28)
                }
            }
            .accessibilityHidden(true)
            .frame(width: width, height: height)
            .foregroundStyle(.white)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint("Opens \(action.title.lowercased()) in Cave Cals")
    }
}

@main struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CalorieWidgetStorage.kind, provider: QuickLogProvider()) { entry in QuickLogView(entry: entry) }
            .configurationDisplayName("Quick Log")
            .description("See today’s calories, scan a barcode, log by voice, scan a meal, or search/add foods.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
