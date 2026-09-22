import SwiftUI
import Charts

struct WeightEditorRoute: Identifiable {
    let id = UUID()
    var record: WeightRecord?
}

struct WeightProfileSections: View {
    @Environment(WeightStore.self) private var weights
    @Binding var editor: WeightEditorRoute?
    var body: some View {
        Group {
            if weights.tracking {
                Section {
                    Button { editor = WeightEditorRoute(record: weights.record(on: Date())) } label: {
                        HStack(spacing: 12) {
                            Text("Today’s weight").foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            CaveIcon(.pencil, size: 22).foregroundStyle(.blue)
                            Text(weights.record(on: Date()).map { weights.unit.text($0.kilograms) } ?? "Not logged yet")
                                .font(.cave(.title3)).foregroundStyle(.primary)
                                .fixedSize(horizontal: true, vertical: false)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todayWeight")
                }
                Section("Weight history") {
                    WeightChartView()
                    NavigationLink("All weigh-ins") { WeightHistoryView() }
                        .accessibilityIdentifier("weightHistory")
                }
            }
            Section {
                Toggle("Track weight", isOn: Binding(get: { weights.tracking }, set: { weights.setTracking($0) }))
                    .accessibilityIdentifier("trackWeight")
                if weights.tracking {
                    Picker("Weight unit", selection: Binding(get: { weights.unit }, set: { weights.setUnit($0) })) {
                        Text("Pounds (lb)").tag(WeightUnit.pounds)
                        Text("Kilograms (kg)").tag(WeightUnit.kilograms)
                    }.accessibilityIdentifier("weightUnit")
                }
            } footer: {
                Text("Optional. Turning this off hides weigh-ins and the daily reminder. Your history is kept on this device.")
            }
            if weights.tracking {
                Section {
                    Toggle("Save to Apple Health", isOn: Binding(get: { weights.healthSharing }, set: { enabled in
                        Task { await weights.setHealthSharing(enabled) }
                    }))
                    .disabled(weights.connecting || !weights.healthAvailable)
                    .accessibilityIdentifier("shareWeightHealth")
                    if weights.connecting || weights.syncing { ProgressView(weights.connecting ? "Connecting…" : "Sharing weigh-ins…") }
                    if let message = weights.healthMessage { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
                    if !weights.healthAvailable { Text("Apple Health is unavailable on this device.").font(.cave(.footnote)).foregroundStyle(.secondary) }
                    if weights.healthSharing && weights.pendingCount > 0 {
                        Button("Retry sharing") { Task { await weights.syncHealth() } }.disabled(weights.syncing)
                    }
                } header: { Text("Apple Health") } footer: {
                    Text("Shares existing and future Cave Cals weigh-ins, including corrections and deletions. No weight data is read from other apps. Connect Trainerize to Apple Health separately to receive supported weight updates. Turning sharing off leaves existing Health entries in place.")
                }
            }
            if let error = weights.error { Section { Text(error).foregroundStyle(.red) } }
        }
    }
}

struct WeightEditorSheet: View {
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    let record: WeightRecord?
    let unit: WeightUnit
    @State private var amount: String
    @State private var date: Date
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    init(record: WeightRecord? = nil, unit: WeightUnit) {
        self.record = record; self.unit = unit
        _date = State(initialValue: record?.date ?? Date())
        _amount = State(initialValue: record.map { unit.editingText($0.kilograms) } ?? "")
    }
    private var kilograms: Double? {
        // Changing only the date must not round-trip a converted display value.
        if let record, amount == unit.editingText(record.kilograms) { return record.kilograms }
        return WeightUnit.parse(amount).map { unit.kilograms($0) }
    }
    private var valid: Bool { kilograms.map(WeightStore.valid) == true && date <= Date() }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Weight", text: $amount)
                            .keyboardType(.decimalPad).focused($focused)
                            .font(.cave(.largeTitle)).accessibilityIdentifier("weightAmount")
                            .accessibilityLabel("Weight in \(unit == .pounds ? "pounds" : "kilograms")")
                        Text(unit.rawValue).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("weightDate")
                } footer: {
                    if record == nil, let existing = weights.record(on: date) {
                        Text("Saving updates this day’s existing weigh-in of \(unit.text(existing.kilograms)).")
                    } else {
                        Text("One weigh-in per day. You can correct it or add a missed day at any time.")
                    }
                }
                if let error = weights.error { Section { Text(error).foregroundStyle(.red) } }
                if record != nil {
                    Section {
                        Button("Delete weigh-in", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("deleteWeight")
                    }
                }
            }
            .navigationTitle(record == nil ? "Weigh-in" : "Edit weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let kilograms else { return }
                        if weights.save(kilograms: kilograms, date: date, id: record?.id) { dismiss() }
                    } label: { Label("Save", systemImage: "checkmark").foregroundStyle(.white) }
                    .buttonStyle(.borderedProminent).tint(.blue).disabled(!valid)
                    .accessibilityIdentifier("saveWeight")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .confirmationDialog("Delete this weigh-in?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete weigh-in", role: .destructive) {
                    if let record, weights.delete(record.id) { dismiss() }
                }
            } message: {
                Text(weights.healthSharing ? "It will also be removed from Apple Health when sharing completes." : "If previously shared, its Apple Health copy will be removed when you resume sharing.")
            }
            .task {
                guard record == nil else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }; focused = true
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct WeightHistoryView: View {
    @Environment(WeightStore.self) private var weights
    @State private var editor: WeightEditorRoute?
    var body: some View {
        List {
            if weights.records.isEmpty { Text("Your weigh-ins will appear here.").foregroundStyle(.secondary) }
            ForEach(weights.records) { record in
                Button { editor = WeightEditorRoute(record: record) } label: {
                    HStack {
                        Text(record.date, format: .dateTime.month(.abbreviated).day().year())
                        Spacer()
                        Text(weights.unit.text(record.kilograms))
                        CaveIcon(.pencil, size: 18).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).frame(minHeight: 44)
                }.accessibilityIdentifier("weight-\(record.id)")
            }
        }
        .navigationTitle("Weigh-ins")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button("Add weigh-in") { editor = WeightEditorRoute() }.accessibilityIdentifier("addHistoricalWeight")
        } }
        .sheet(item: $editor) { route in WeightEditorSheet(record: route.record, unit: weights.unit) }
    }
}

struct WeightChartView: View {
    @Environment(WeightStore.self) private var weights
    @State private var range = WeightChartRange.month
    @State private var selectedDate: Date?
    @State private var endDate = Date()
    private var interval: DateInterval { range.interval(endingAt: endDate) }
    private var points: [WeightChartPoint] { range.points(weights.records, endingAt: endDate) }
    private var selected: WeightChartPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var domain: ClosedRange<Double> {
        let values = points.map { weights.unit.display($0.kilograms) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(weights.unit == .pounds ? 2 : 1, (high - low) * 0.2)
        return max(0, low - padding)...(high + padding)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Chart period", selection: $range) {
                ForEach(WeightChartRange.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("weightChartRange")
            HStack {
                Button { move(-1) } label: { CaveIcon(.chevronLeft, size: 16).frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous weight period")
                Spacer(minLength: 0)
                Text(periodLabel).font(.cave(.caption)).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { move(1) } label: { CaveIcon(.chevronRight, size: 16).frame(width: 44, height: 44) }
                    .disabled(Calendar.current.isDate(endDate, inSameDayAs: Date()))
                    .accessibilityLabel("Next weight period")
            }.buttonStyle(.borderless)
            if points.isEmpty {
                VStack(spacing: 8) {
                    Text("No weigh-ins in this period").font(.cave(.headline))
                    Text("Log a weight to start your graph.").font(.cave(.subheadline)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 170)
            } else {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", weights.unit.display(point.kilograms)), series: .value("Recorded period", segment(at: index)))
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Date", point.date), y: .value("Weight", weights.unit.display(point.kilograms)))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue(weights.unit.text(point.kilograms))
                    }
                    if let selected {
                        RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXScale(domain: interval.start...interval.end)
                .chartYScale(domain: domain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: range == .week ? 4 : 3)) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartXSelection(value: $selectedDate)
                .chartLegend(.hidden)
                .frame(height: 170).accessibilityIdentifier("weightChart")
                if let point = selected ?? points.last {
                    Text("\(weights.unit.text(point.kilograms)) · \(point.date.formatted(range == .year ? .dateTime.month(.wide).year() : .dateTime.month(.abbreviated).day()))\(range == .year ? " · \(point.count) weigh-ins" : "")")
                        .font(.cave(.subheadline)).accessibilityIdentifier("weightChartValue")
                }
            }
            Text(range == .year ? "Monthly averages · \(weights.unit.rawValue). Only recorded days contribute." : "Daily weigh-ins · \(weights.unit.rawValue). Gaps are days without a weigh-in.")
                .font(.cave(.caption)).foregroundStyle(.secondary)
        }
        .onChange(of: range) { _, _ in selectedDate = nil; endDate = Date() }
    }
    private var periodLabel: String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)!
        return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + lastDay.formatted(.dateTime.month(.abbreviated).day().year())
    }
    private func move(_ direction: Int) {
        let component: Calendar.Component = range == .year ? .year : .day
        let count = range == .year ? 1 : (range == .week ? 7 : 30)
        endDate = min(Date(), Calendar.current.date(byAdding: component, value: direction * count, to: endDate)!)
        selectedDate = nil
    }
    // Separate line segments avoid implying measurements across missing days/months.
    private func segment(at index: Int) -> Int {
        guard index > 0 else { return 0 }
        let component: Calendar.Component = range == .year ? .month : .day
        return (1...index).reduce(0) { total, offset in
            total + ((Calendar.current.dateComponents([component], from: points[offset - 1].date, to: points[offset].date).value(for: component) ?? 0) > 1 ? 1 : 0)
        }
    }
}
