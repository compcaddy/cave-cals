import SwiftUI
import Charts

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    /// Synced on the profile (`ProgressSettings`), like the rest of Progress's settings.
    private var firstWeekday: Int { store.progressSettings.firstWeekday }
    @State private var reviewDate: Date?
    @State private var printReport: ProgressPrintDocument?
    @State private var showPrint = false
    private var data: ProgressData {
        ProgressData(drafts: store.entries.map(EntryDraft.init), records: weights.records,
                     finishedDays: store.finishedDates(), firstWeekday: firstWeekday, goal: { store.goal($0) })
    }
    private var selectedReviewDate: Date { reviewDate ?? data.currentWeekStart }
    /// “How averages work” is hidden for now (October 6, 2026); this was its text, for when it returns.
    static let averagesExplanation = "Calories average only completed days. A day below 70% of that day's calorie goal is marked incomplete unless you marked it done eating; without a goal, the reference is your usual completed-day calories over the prior 28 days. Today is still in progress. Weight averages use recorded weigh-ins only. Missing days never count as zero."

    var body: some View {
        let data = data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WeeklyProgressReview(data: data, selected: selectedReviewDate, unit: weights.unit) { reviewDate = $0 }
                    ProgressNutritionChart(data: data)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weight history").font(.cave(.title2)).bold()
                        ProgressWeightChart(data: data, unit: weights.unit)
                        NavigationLink { WeightHistoryView().hapticOnPush() } label: {
                            HStack { Text("All weigh-ins"); Spacer(); CaveIcon(.chevronRight, size: 16) }
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("weightHistory")
                        if !weights.tracking {
                            Text("Turn on Track weight in About You to log weigh-ins.")
                                .font(.cave(.footnote)).foregroundStyle(Color.secondary)
                        }
                    }.progressCard()
                    ProgressPhotosCard(firstWeekday: firstWeekday)
                    VStack(alignment: .leading, spacing: 12) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { Text("Weekday Start"); Spacer(minLength: 0); weekStartPicker }
                            VStack(alignment: .leading, spacing: 4) { Text("Weekday Start"); weekStartPicker }
                        }
                        Text("Applies to charts, weekly recaps, photos, and printed reports.")
                            .font(.cave(.footnote)).foregroundStyle(Color.secondary)
                    }.progressCard()
                    ProgressTrendsCard(data: data, foods: store.entries.map {
                        ProgressTrends.Food(timestamp: $0.timestamp, createdAt: $0.createdAt, calories: $0.totalCalories)
                    })
                    ProgressHabitsCard(data: data, foods: store.entries.map { entry in
                        HabitFood(timestamp: entry.timestamp, createdAt: entry.createdAt, calories: entry.totalCalories,
                                  name: entry.foodDisplayName, macros: MacroNutrients.decode(entry.macrosPerServingData)?.scaled(entry.servings))
                    }, goal: { store.goal($0) })
                }.padding(20)
            }
            .background(Color.caveBackground)
            .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let weeks = data.fiveWeeks(endingAt: selectedReviewDate)
                        printReport = ProgressPrintDocument(weeks: weeks, dates: data.dates, unit: weights.unit,
                            dailyGoal: store.goal(Date()), priorWeek: weeks.first.map { data.week(containing: data.dates.move($0.interval.start, by: -1, period: .week)) },
                            isInProgress: weeks.last.map { $0.interval.end > data.today } ?? false)
                        showPrint = true
                    } label: { Image(systemName: "printer").frame(minWidth: 44, minHeight: 44) }
                    .hapticButtonStyle(.automatic)
                    .accessibilityLabel("Print weekly recap and five-week trends").accessibilityIdentifier("printProgress")
                }
            }
            .sheet(isPresented: $showPrint) {
                if let printReport { ProgressPrintPreview(document: printReport) }
            }
            .onChange(of: store.progressSettings.firstWeekday) { _, _ in reviewDate = nil }
        }
    }

    private var weekStartPicker: some View {
        Picker("Weekday Start", selection: Binding(get: { store.progressSettings.firstWeekday }, set: { weekday in
            var settings = store.progressSettings
            settings.firstWeekday = weekday
            store.saveProgressSettings(settings)
        })) {
            ForEach(1...7, id: \.self) { day in
                Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
            }
        }
        .labelsHidden()
        .frame(minHeight: 44)
        .hapticSelection(on: firstWeekday)
        .accessibilityIdentifier("progressWeekStart")
    }
}

extension View {
    func progressCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ProgressPeriodPicker: View {
    let dates: ProgressCalendar
    @Binding var period: ProgressPeriod
    @Binding var date: Date
    let identifier: String
    var body: some View {
        VStack(spacing: 4) {
            Picker("Chart period", selection: $period) {
                ForEach(ProgressPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).hapticSelection(on: period).accessibilityIdentifier(identifier)
            ProgressDateNavigation(label: dates.label(dates.interval(period, containing: date)),
                canGoForward: dates.interval(period, containing: date).end <= Date(), identifier: identifier) { direction in
                    date = dates.move(dates.interval(period, containing: date).start, by: direction, period: period)
                }
        }
    }
}

struct ProgressDateNavigation: View {
    let label: String
    let canGoForward: Bool
    let identifier: String
    let move: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button { move(-1) } label: { CaveIcon(.chevronLeft, size: 16).frame(width: 44, height: 44) }
                .accessibilityLabel("Previous period").accessibilityIdentifier(identifier + "Previous")
            Text(label).font(.cave(.footnote)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Button { move(1) } label: { CaveIcon(.chevronRight, size: 16).frame(width: 44, height: 44) }
                .disabled(!canGoForward).accessibilityLabel("Next period").accessibilityIdentifier(identifier + "Next")
        }.hapticButtonStyle(.borderless).hapticFeel(.selection)
    }
}

struct WeeklyProgressReview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let data: ProgressData
    let selected: Date
    let unit: WeightUnit
    let move: (Date) -> Void
    @State private var showDays = false
    private var week: ProgressWeek { data.week(containing: selected) }
    private var previous: ProgressWeek { data.week(containing: data.dates.move(selected, by: -1, period: .week)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weekly Recap").font(.cave(.title2)).bold()
                Spacer()
                if week.interval.end > data.today {
                    Text("In progress").font(.cave(.caption)).foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("reviewWeekStatus")
                }
            }
            ProgressDateNavigation(label: data.dates.label(week.interval),
                canGoForward: week.interval.end <= data.today, identifier: "reviewWeek") { direction in
                    move(data.dates.move(week.interval.start, by: direction, period: .week))
                }
            reviewMetric("Average weight", stats: week.weight, previous: previous.weight, weight: true)
            reviewMetric("Average daily calories", stats: week.calories, previous: previous.calories, weight: false)
            Text("Compared with \(data.dates.label(previous.interval)).")
                .font(.cave(.footnote)).foregroundStyle(Color.secondary)
            DisclosureGroup("Daily breakdown", isExpanded: $showDays) {
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack { Text("Day"); Spacer(); Text("Calories").frame(width: 100, alignment: .trailing); Text(unit.rawValue).frame(width: 66, alignment: .trailing) }
                            .font(.cave(.caption)).foregroundStyle(Color.secondary).padding(.vertical, 10)
                    }
                    ForEach(week.days) { day in
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                Text((day.calories?.calorieText ?? "—") + " calories")
                                if day.status != .complete { Text(day.status.label).foregroundStyle(Color.secondary) }
                                Text(day.weight.map { unit.text($0) } ?? "No weigh-in")
                            }.font(.cave(.subheadline)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12).accessibilityElement(children: .combine)
                        } else {
                        HStack(alignment: .top) {
                            Text(day.date, format: .dateTime.weekday(.abbreviated).day()).frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(day.calories?.calorieText ?? "—")
                                if day.status != .complete {
                                    Text(day.status.label).font(.cave(.caption2)).foregroundStyle(Color.secondary)
                                }
                            }.frame(width: 100, alignment: .trailing)
                            Text(day.weight.map { unit.display($0).formatted(.number.precision(.fractionLength(1))) } ?? "—")
                                .frame(width: 66, alignment: .trailing)
                        }.font(.cave(.subheadline)).padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                        }
                        if day.id != week.days.last?.id { Divider() }
                    }
                }
            }.accessibilityIdentifier("progressDailyBreakdown").accessibilityValue(showDays ? "Expanded" : "Collapsed")
        }
        .onChange(of: selected) { _, _ in showDays = false }
    }
    private func reviewMetric(_ title: String, stats: ProgressStats, previous: ProgressStats, weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.cave(.headline))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 22) {
                    metricDetails(stats, weight: weight).fixedSize(horizontal: true, vertical: false)
                    metricTrend(stats: stats, previous: previous, weight: weight).frame(minWidth: 130)
                }
                VStack(alignment: .leading, spacing: 14) {
                    metricDetails(stats, weight: weight)
                    metricTrend(stats: stats, previous: previous, weight: weight)
                }
            }
        }.progressCard()
    }
    private func metricDetails(_ stats: ProgressStats, weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            InkBoldText(format(stats.average, weight: weight), font: .cave(.largeTitle), weight: 0.65)
                .accessibilityIdentifier(weight ? "reviewWeightAverage" : "reviewCalorieAverage")
            Text("Range: " + rangeNumber(stats.min, weight: weight) + " to " + rangeNumber(stats.max, weight: weight))
                .font(.cave(.footnote)).foregroundStyle(Color.secondary)
            Text("\(stats.count) of 7 \(weight ? "weigh-ins" : "completed days")")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
    }
    private func metricTrend(stats: ProgressStats, previous: ProgressStats, weight: Bool) -> some View {
        let change = ProgressFormat.change(stats.change(from: previous), unit: weight ? unit : nil)
        let amount = change.replacingOccurrences(of: " vs prior week", with: "")
        return VStack(alignment: .trailing, spacing: 10) {
            // The change sits right-aligned above the chart, with its comparison on a second line.
            VStack(alignment: .trailing, spacing: 2) {
                InkBoldText(amount, font: .cave(.subheadline), weight: 0.45)
                if change.contains("vs prior week") { Text("versus prior week").font(.cave(.caption)) }
            }
            .multilineTextAlignment(.trailing)
            .foregroundStyle(Color.caveOrange)
            .accessibilityElement(children: .combine)
            RecapMiniChart(days: week.days, unit: unit, weight: weight)
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func rangeNumber(_ value: Double?, weight: Bool) -> String {
        value.map { weight ? unit.display($0).formatted(.number.precision(.fractionLength(1))) : $0.calorieText } ?? "—"
    }

    private func format(_ value: Double?, weight: Bool) -> String {
        value.map { weight ? unit.text($0) : $0.calorieText + " cals" } ?? "—"
    }
}

private struct RecapMiniChart: View {
    @ScaledMetric(relativeTo: .caption2) private var chartHeight = 82.0
    let days: [ProgressDay]
    let unit: WeightUnit
    let weight: Bool
    private var domain: ClosedRange<Double> {
        let values = days.compactMap { weight ? $0.weight.map(unit.display) : $0.calories }
        let low = weight ? (values.min() ?? 0) : 0
        let high = values.max() ?? 1
        let padding = weight ? max(0.2, (high - low) * 0.3) : max(1, high * 0.1)
        return max(0, low - (weight ? padding : 0))...max(1, high + padding)
    }
    var body: some View {
        Chart {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if weight, let value = day.weight {
                    let segment = days.prefix(index).filter { $0.weight == nil }.count
                    LineMark(x: .value("Day", index), y: .value("Weight", unit.display(value)), series: .value("Segment", segment))
                        .foregroundStyle(Color.caveOrange)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Day", index), y: .value("Weight", unit.display(value)))
                        .foregroundStyle(Color.caveOrange).symbolSize(10)
                } else if !weight, let value = day.calories {
                    RectangleMark(xStart: .value("Day", Double(index) - 0.28), xEnd: .value("Day", Double(index) + 0.28),
                                  yStart: .value("Calories", 0), yEnd: .value("Calories", value))
                        .foregroundStyle(Color.caveOrange.opacity(day.status == .complete ? 0.7 : 0.22))
                }
            }
        }
        .chartXScale(domain: -0.5...6.5).chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: Array(days.indices)) { value in
                AxisTick(length: 3, stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                AxisValueLabel(centered: false, anchor: .top) {
                    if let index = value.as(Int.self), days.indices.contains(index) {
                        Text(days[index].date, format: .dateTime.weekday(.narrow))
                            .font(.custom("Schoolbell-Regular", size: 11, relativeTo: .caption2))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(weight
                            ? number.formatted(.number.precision(.fractionLength(1)))
                            : number.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                            .font(.custom("Schoolbell-Regular", size: 11, relativeTo: .caption2))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .overlay(alignment: .bottom) { Color.secondary.opacity(0.3).frame(height: 0.5) }
                .overlay(alignment: .trailing) { Color.secondary.opacity(0.3).frame(width: 0.5) }
        }
        .chartLegend(.hidden)
        .frame(height: chartHeight)
        .accessibilityHidden(true)
    }
}

enum ProgressFormat {
    static func goalChange(average: Double?, goal: Double?) -> String {
        guard let goal, goal > 0 else { return "No daily goal set" }
        guard let average else { return "No completed calorie days" }
        let difference = (average - goal).rounded()
        if difference == 0 { return "On goal" }
        return "\(difference < 0 ? "↓" : "↑") \(abs(difference).calorieText) cals \(difference < 0 ? "below" : "above") goal"
    }
    static func signedChange(_ value: Double?, unit: WeightUnit?) -> String {
        guard let value else { return "—" }
        let places = unit == nil ? 1.0 : 10.0
        let display = ((unit.map { $0.display(value) } ?? value) * places).rounded() / places
        let amount = unit == nil ? abs(display).calorieText : abs(display).formatted(.number.precision(.fractionLength(1)))
        return (display == 0 ? "" : display < 0 ? "-" : "+") + amount
    }
    static func change(_ value: Double?, unit: WeightUnit?) -> String {
        guard let value else { return "No comparison yet" }
        let display = unit.map { $0.display(value) } ?? value
        let rounded = (display * (unit == nil ? 1 : 10)).rounded()
        if rounded == 0 { return "No change" }
        let amount = unit == nil ? abs(display).calorieText : abs(display).formatted(.number.precision(.fractionLength(1)))
        return "\(value < 0 ? "↓" : "↑") \(amount) \(unit?.rawValue ?? "cals") vs prior week"
    }
}

enum NutritionChartMode: String, CaseIterable, Identifiable {
    case calories = "Calories", breakdown = "Macro breakdown", protein = "Protein", carbs = "Carbs", fat = "Fat"
    var id: Self { self }
    var macro: MacroKind? { switch self { case .protein: .protein; case .carbs: .totalCarbs; case .fat: .fat; default: nil } }
}

struct ProgressNutritionChart: View {
    let data: ProgressData
    @State private var period: ProgressPeriod = .week
    @State private var date = Date()
    @State private var mode: NutritionChartMode = .breakdown
    @State private var selection: Date?
    private let names = ["Protein", "Carbs", "Fat", "Unknown"]
    private let colors: [Color] = [.caveOrange, Color(red: 0.88, green: 0.53, blue: 0.23), Color(red: 0.63, green: 0.36, blue: 0.18), .gray.opacity(0.65)]
    private var buckets: [ProgressBucket] { data.buckets(period, containing: date) }
    private var selected: ProgressBucket? {
        guard let selection else { return buckets.last { $0.calories != nil } }
        return buckets.first { selection >= $0.start && selection < $0.end }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calories & macros").font(.cave(.title2)).bold()
            ProgressPeriodPicker(dates: data.dates, period: $period, date: $date, identifier: "nutritionChartRange")
            Picker("Show", selection: $mode) {
                ForEach(NutritionChartMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).hapticSelection(on: mode).accessibilityIdentifier("nutritionChartMode")
            chart
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.start, format: .dateTime.month(.abbreviated).day())
                        .font(.cave(.caption)).foregroundStyle(Color.secondary)
                    Text(valueLabel(selected)).font(.cave(.subheadline)).accessibilityIdentifier("nutritionChartValue")
                    if period == .year {
                        Text(mode.macro.map { "Daily average · \(selected.macroDayCounts[$0] ?? 0) of \(selected.includedDays) completed days with values" }
                             ?? "Daily average · \(selected.includedDays) completed days")
                            .font(.cave(.caption)).foregroundStyle(Color.secondary)
                    } else if selected.status != .complete {
                        Text(selected.status.label + (selected.status == .incomplete ? " · excluded from averages" : ""))
                            .font(.cave(.caption)).foregroundStyle(Color.secondary)
                    }
                }
            } else { Text("No food logged in this period.").font(.cave(.subheadline)).foregroundStyle(Color.secondary) }
            Text(mode == .breakdown ? "Approximate split · unknown includes calories without matching macro values. Tap a bar for its total." : "Tap a bar for details. Faded days are incomplete or still in progress.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
            if mode.macro != nil {
                Text("Known grams only; missing macros stay unknown. Year averages use completed calorie days with recorded macro values.")
                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
            }
        }.progressCard()
        .onChange(of: period) { _, _ in selection = nil }
        .onChange(of: date) { _, _ in selection = nil }
    }
    private var chart: some View {
        let buckets = buckets
        return Chart {
            ForEach(buckets) { bucket in
                nutritionMarks(bucket)
            }
            if let selection { RuleMark(x: .value("Selected", selection)).foregroundStyle(Color.secondary.opacity(0.3)) }
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(mode == .breakdown ? .visible : .hidden)
        .chartXScale(domain: data.dates.interval(period, containing: date).start...data.dates.interval(period, containing: date).end)
        .chartXAxis {
            if period == .week {
                AxisMarks(values: buckets.map(\.center)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            } else if period == .month {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            } else { AxisMarks(values: .automatic(desiredCount: 5)) }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartXSelection(value: $selection)
        // One tick per column while scrubbing, not per point.
        .onChange(of: selection.flatMap { value in buckets.first { value >= $0.start && value < $0.end }?.start }) { _, start in
            if start != nil { Haptics.play(.selection) }
        }
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .frame(height: 220).accessibilityIdentifier("nutritionChart")
    }
    private func chartValue(_ bucket: ProgressBucket) -> Double? {
        if let macro = mode.macro { return bucket.grams(macro) }
        return bucket.calories
    }
    @ChartContentBuilder private func nutritionMarks(_ bucket: ProgressBucket) -> some ChartContent {
        if let value = chartValue(bucket) {
            if mode == .breakdown {
                let amounts = [bucket.energy.protein, bucket.energy.carbs, bucket.energy.fat, bucket.energy.unknown]
                ForEach(0..<4, id: \.self) { index in
                    RectangleMark(xStart: .value("Date", barStart(bucket)), xEnd: .value("Date", barEnd(bucket)),
                                  yStart: .value("Calories", amounts.prefix(index).reduce(0, +)),
                                  yEnd: .value("Calories", amounts.prefix(index + 1).reduce(0, +)))
                        .foregroundStyle(by: .value("Macro", names[index]))
                        .opacity(opacity(bucket))
                        .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted) + ", " + names[index])
                        .accessibilityValue(amounts[index].calorieText + " calories, " + bucket.status.label)
                }
            } else {
                RectangleMark(xStart: .value("Date", barStart(bucket)), xEnd: .value("Date", barEnd(bucket)),
                              yStart: .value("Amount", 0), yEnd: .value("Amount", value))
                    .foregroundStyle(Color.caveOrange).opacity(opacity(bucket))
                    .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(valueLabel(bucket))
            }
            if period == .week {
                PointMark(x: .value("Date", bucket.center), y: .value("Total", value)).symbolSize(0)
                    .annotation(position: .top) { Text(value.calorieText).font(.system(size: 10)).foregroundStyle(Color.secondary) }
            }
        }
    }
    // Explicit date intervals preserve visible column widths, including clipped weeks at year edges.
    private func barStart(_ bucket: ProgressBucket) -> Date { bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) * 0.125) }
    private func barEnd(_ bucket: ProgressBucket) -> Date { bucket.end.addingTimeInterval(-bucket.end.timeIntervalSince(bucket.start) * 0.125) }
    private func opacity(_ bucket: ProgressBucket) -> Double { bucket.status == .complete ? 1 : 0.4 }
    private func valueLabel(_ bucket: ProgressBucket) -> String {
        if let macro = mode.macro {
            return bucket.grams(macro).map { "\($0.macroText) g \(macro.title.lowercased())\(bucket.partialMacros ? " · partial data" : "")" } ?? "Macro values unknown"
        }
        return bucket.calories.map { "\($0.calorieText) calories" } ?? "Not logged"
    }
}

struct ProgressWeightChart: View {
    let data: ProgressData
    let unit: WeightUnit
    @State private var period: ProgressPeriod = .month
    @State private var date = Date()
    @State private var selection: Date?
    private var buckets: [ProgressBucket] { data.buckets(period, containing: date) }
    private var selected: ProgressBucket? {
        guard let selection else { return buckets.last { $0.weight != nil } }
        return buckets.first { selection >= $0.start && selection < $0.end }
    }
    private var domain: ClosedRange<Double> {
        let values = buckets.compactMap { $0.weight.map(unit.display) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(unit == .pounds ? 2 : 1, (high - low) * 0.2)
        return max(0, low - padding)...(high + padding)
    }
    var body: some View {
        let buckets = buckets
        VStack(alignment: .leading, spacing: 12) {
            ProgressPeriodPicker(dates: data.dates, period: $period, date: $date, identifier: "weightChartRange")
            if buckets.contains(where: { $0.weight != nil }) {
                Chart {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        if let weight = bucket.weight {
                            LineMark(x: .value("Date", bucket.center), y: .value("Weight", unit.display(weight)),
                                     series: .value("Segment", segment(at: index, in: buckets)))
                                .foregroundStyle(Color.caveOrange)
                            PointMark(x: .value("Date", bucket.center), y: .value("Weight", unit.display(weight)))
                                .foregroundStyle(Color.caveOrange)
                                .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(unit.text(weight))
                        }
                    }
                    if let selection { RuleMark(x: .value("Selected", selection)).foregroundStyle(Color.secondary.opacity(0.3)) }
                }
                .chartXScale(domain: data.dates.interval(period, containing: date).start...data.dates.interval(period, containing: date).end)
                .chartYScale(domain: domain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartLegend(.hidden).chartXSelection(value: $selection)
                // One tick per column while scrubbing, not per point.
                .onChange(of: selection.flatMap { value in buckets.first { value >= $0.start && value < $0.end }?.start }) { _, start in
                    if start != nil { Haptics.play(.selection) }
                }
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
                .frame(height: 190).accessibilityIdentifier("weightChart")
                if let selected, let weight = selected.weight {
                    Text("\(unit.text(weight)) · \(selected.start.formatted(.dateTime.month(.abbreviated).day()))\(period == .year ? " · \(selected.weighIns) weigh-ins" : "")")
                        .font(.cave(.subheadline)).accessibilityIdentifier("weightChartValue")
                }
            } else {
                Text("No weigh-ins in this period").font(.cave(.subheadline))
                    .foregroundStyle(Color.secondary).frame(maxWidth: .infinity, minHeight: 130)
            }
            Text(period == .year ? "Weekly averages · \(unit.rawValue). Only recorded weigh-ins contribute." : "Daily weigh-ins · \(unit.rawValue). Gaps are days without a weigh-in.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
        .onChange(of: period) { _, _ in selection = nil }
        .onChange(of: date) { _, _ in selection = nil }
    }
    private func segment(at index: Int, in buckets: [ProgressBucket]) -> Int { buckets.prefix(index).filter { $0.weight == nil }.count }
}

/// Progress → Trends: average calories by weekday and by hour of the day, over complete days in the chosen range.
struct ProgressTrendsCard: View {
    let data: ProgressData
    let foods: [ProgressTrends.Food]
    @Environment(AppStore.self) private var store
    /// Synced with the other Progress settings.
    private var range: ProgressTrendRange { store.progressSettings.trendsRange }
    @State private var hourMode: HourMode = .calories
    @State private var selectedWeekday: String?
    @State private var selectedHour: String?

    enum HourMode: String, CaseIterable, Identifiable {
        case calories = "Calories", share = "% of day"
        var id: Self { self }
    }

    var body: some View {
        let trends = ProgressTrends(foods: foods, data: data, range: range)
        VStack(alignment: .leading, spacing: 14) {
            Text("Trends").font(.cave(.title2)).bold()
            Picker("Range", selection: Binding(get: { range }, set: { value in
                var settings = store.progressSettings
                settings.trendsRange = value
                store.saveProgressSettings(settings)
            })) {
                ForEach(ProgressTrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).hapticSelection(on: range)
            .accessibilityIdentifier("trendsRange")

            Text("By day of the week").font(.cave(.headline)).padding(.top, 4)
            if trends.weekdayDays == 0 {
                emptyNote
            } else {
                weekdayChart(trends)
                Text(weekdayDetail(trends)).font(.cave(.subheadline))
                    .accessibilityIdentifier("trendsWeekdayDetail")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("By time of day").font(.cave(.headline))
                Spacer(minLength: 8)
                Picker("Show", selection: $hourMode) {
                    ForEach(HourMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize().hapticSelection(on: hourMode)
                .accessibilityIdentifier("trendsHourMode")
            }
            .padding(.top, 8)
            if trends.hourDays == 0 {
                emptyNote
            } else {
                hourChart(trends)
                Text(hourDetail(trends)).font(.cave(.subheadline))
                    .accessibilityIdentifier("trendsHourDetail")
                Text("Food added on a later day is left out here, since its time isn’t when it was eaten.")
                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
            }
        }
        .progressCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressTrends")
        .onChange(of: range) { _, new in
            selectedWeekday = nil; selectedHour = nil
            UsageStats.shared.event("progress.trends", ["range": new.statName])
        }
        .onChange(of: hourMode) { _, new in
            UsageStats.shared.event("progress.trends", ["hours": new == .calories ? "calories" : "share"])
        }
    }

    private var emptyNote: some View {
        Text("Not enough complete days in this range yet.")
            .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
    }

    // MARK: Weekdays

    private func short(_ weekday: Int) -> String { data.dates.calendar.shortWeekdaySymbols[weekday - 1] }

    private func weekdayChart(_ trends: ProgressTrends) -> some View {
        Chart(trends.weekdays) { day in
            BarMark(x: .value("Day", short(day.weekday)), y: .value("Calories", day.average ?? 0))
                .foregroundStyle(Color.caveOrange.opacity(selectedWeekday == nil || selectedWeekday == short(day.weekday) ? 1 : 0.35))
                .cornerRadius(4)
                .accessibilityLabel(data.dates.calendar.weekdaySymbols[day.weekday - 1])
                .accessibilityValue(day.average.map { "\($0.calorieText) calories on average, \(day.days) days" } ?? "No complete days")
        }
        .chartXScale(domain: trends.weekdays.map { short($0.weekday) })
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartXSelection(value: $selectedWeekday)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .onChange(of: selectedWeekday) { _, value in if value != nil { Haptics.play(.selection) } }
        .frame(height: 180)
        .accessibilityIdentifier("trendsWeekdayChart")
    }

    private func weekdayDetail(_ trends: ProgressTrends) -> String {
        if let selectedWeekday, let day = trends.weekdays.first(where: { short($0.weekday) == selectedWeekday }) {
            let name = data.dates.calendar.weekdaySymbols[day.weekday - 1]
            guard let average = day.average else { return "\(name): no complete days" }
            return "\(name): \(average.calorieText) cals on average · \(day.days) \(day.days == 1 ? "day" : "days")"
        }
        return "Average calories on complete days · based on \(trends.weekdayDays) \(trends.weekdayDays == 1 ? "day" : "days"). Tap a bar."
    }

    // MARK: Hours

    private static let hourLabels = ["0": "12a", "6": "6a", "12": "12p", "18": "6p"]

    private func hourValue(_ hour: ProgressTrends.Hour) -> Double { hourMode == .calories ? hour.calories : hour.share * 100 }

    private func hourChart(_ trends: ProgressTrends) -> some View {
        Chart(trends.hours) { hour in
            BarMark(x: .value("Hour", String(hour.hour)), y: .value(hourMode.rawValue, hourValue(hour)))
                .foregroundStyle(Color.caveOrange.opacity(selectedHour == nil || selectedHour == String(hour.hour) ? 1 : 0.35))
                .cornerRadius(2)
                .accessibilityLabel(hourRange(hour.hour))
                .accessibilityValue(hourText(hour))
        }
        .chartXScale(domain: (0..<24).map(String.init))
        .chartXAxis {
            AxisMarks(values: ["0", "6", "12", "18"]) { value in
                AxisGridLine()
                // The first label sits at the chart's edge; never shorten it to "…".
                AxisValueLabel(collisionResolution: .disabled) {
                    Text(value.as(String.self).flatMap { Self.hourLabels[$0] } ?? "").fixedSize()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { Text(value.as(Double.self).map { hourMode == .calories ? $0.calorieText : "\(Int($0))%" } ?? "") }
            }
        }
        .chartXSelection(value: $selectedHour)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .onChange(of: selectedHour) { _, value in if value != nil { Haptics.play(.selection) } }
        .frame(height: 180)
        .accessibilityIdentifier("trendsHourChart")
    }

    private func hourText(_ hour: ProgressTrends.Hour) -> String {
        hourMode == .calories ? "\(hour.calories.calorieText) cals a day"
            : "\((hour.share * 100).formatted(.number.precision(.fractionLength(0))))% of the day’s calories"
    }

    /// "12 PM – 1 PM"
    private func hourRange(_ hour: Int) -> String {
        func label(_ hour: Int) -> String {
            let date = data.dates.calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: data.today) ?? data.today
            return date.formatted(.dateTime.hour())
        }
        return "\(label(hour)) – \(label(hour + 1))"
    }

    private func hourDetail(_ trends: ProgressTrends) -> String {
        if let selectedHour, let hour = trends.hours.first(where: { String($0.hour) == selectedHour }) {
            return "\(hourRange(hour.hour)): \(hourText(hour))"
        }
        let days = "\(trends.hourDays) \(trends.hourDays == 1 ? "day" : "days")"
        return (hourMode == .calories ? "Average calories in each hour" : "Share of the day’s calories in each hour")
            + " · based on \(days). Tap a bar."
    }
}
