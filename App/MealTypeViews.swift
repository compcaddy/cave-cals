import SwiftUI

/// One-tap meal choice: a chip per meal type, wrapping onto as many lines as it needs. The selected chip is
/// solid orange like Home's pills.
struct MealTypePicker: View {
    let types: [MealType]
    @Binding var selection: String?
    /// Editing logged food can take it out of every meal.
    var allowsNone = false

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 2) {
            ForEach(types) { type in chip(type.name, id: type.id) }
            if allowsNone { chip("None", id: nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal")
        .accessibilityIdentifier("mealTypePicker")
    }

    private func chip(_ title: String, id: String?) -> some View {
        let selected = selection == id
        return Button {
            selection = id
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(selected ? Color.caveOrange : Color(.secondarySystemFill), in: Capsule())
                // The visible chip is 38 points; the tap area is a full 44.
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .hapticButtonStyle(.borderless)
        .hapticFeel(.selection)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mealChip-\(id ?? "none")")
    }
}

/// Lays views out left to right, starting a new line whenever the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}

/// Settings → Meal types: whether food is sorted into meals, how a meal is picked, and the list itself.
struct MealTypeSettingsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let settings = store.mealSettings
        Section {
            Toggle("Track meal type", isOn: binding(\.tracks))
                .accessibilityIdentifier("trackMealTypes")
            if settings.tracks {
                Toggle("Set meal by time of day", isOn: binding(\.byTime))
                    .accessibilityIdentifier("mealTypesByTime")
                NavigationLink {
                    MealTypesScreen().hapticOnPush()
                } label: {
                    HStack {
                        Text("Meal types").foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(settings.visibleTypes.count)").foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityIdentifier("editMealTypes")
            }
        } header: {
            Text("Meal types")
        } footer: {
            Text(footer(settings)).font(.cave(.caption2))
        }
    }

    private func footer(_ settings: MealSettings) -> String {
        if !settings.tracks { return "Sort your log into meals like Breakfast, Lunch, and Dinner." }
        if settings.byTime {
            return "Food goes in the meal whose time it’s logged in; food logged outside every meal’s time has no meal. Long-press logged food to move it."
        }
        return "Adding food asks which meal it’s for."
    }

    private func binding(_ keyPath: WritableKeyPath<MealSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.mealSettings[keyPath: keyPath] }, set: { value in
            var settings = store.mealSettings
            settings[keyPath: keyPath] = value
            withAnimation { _ = store.saveMealSettings(settings) }
        })
    }
}

/// The meal list: rename, retime, reorder, add, or delete meal types.
struct MealTypesScreen: View {
    @Environment(AppStore.self) private var store
    @State private var editing: MealTypeRoute?

    var body: some View {
        let settings = store.mealSettings
        HapticList {
            if settings.byTime {
                Section {
                    MealDayStrip(settings: settings)
                        .listRowBackground(Color.caveSurface)
                }
            }
            Section {
                ForEach(settings.visibleTypes) { type in
                    Button { editing = MealTypeRoute(type: type) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.name).foregroundStyle(Color.primary)
                                Text(type.time?.text ?? "No set time")
                                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
                            }
                            Spacer(minLength: 8)
                            CaveIcon(.chevronRight, size: 14).foregroundStyle(Color.secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("mealType-\(type.id)")
                    .listRowBackground(Color.caveSurface)
                }
                .onMove { source, destination in
                    store.saveMealSettings(store.mealSettings.moving(fromOffsets: source, toOffset: destination))
                }
                Button { editing = MealTypeRoute(type: nil) } label: {
                    Label { Text("Add meal type") } icon: { CaveIcon(.plus, size: 18) }
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("addMealType")
                .listRowBackground(Color.caveSurface)
            } footer: {
                Text(settings.byTime
                     ? "Each meal type has one time of day; for snacks at different times, add a type for each. Home lists meals in this order. Tap Edit to reorder."
                     : "Home lists meals in this order. Tap Edit to reorder.")
                    .font(.cave(.caption2))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.caveBackground)
        .navigationTitle("Meal Types").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton().hapticButtonStyle(.automatic) } }
        .sheet(item: $editing) { route in MealTypeEditorSheet(type: route.type) }
    }
}

struct MealTypeRoute: Identifiable {
    let id = UUID()
    let type: MealType?
}

/// The day as a bar, so gaps and the order of meal times are easy to see at a glance.
struct MealDayStrip: View {
    let settings: MealSettings

    var body: some View {
        let timed = settings.visibleTypes.filter { $0.time != nil }
        let gaps = settings.uncoveredTimes
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.secondarySystemFill))
                    ForEach(Array(timed.enumerated()), id: \.element.id) { index, type in
                        ForEach(Array(segments(type.time!).enumerated()), id: \.offset) { _, segment in
                            Rectangle()
                                .fill(Color.caveOrange.opacity(index.isMultiple(of: 2) ? 0.9 : 0.55))
                                .frame(width: max(2, width * CGFloat(segment.upperBound - segment.lowerBound) / CGFloat(MealTime.minutesInDay)))
                                .offset(x: width * CGFloat(segment.lowerBound) / CGFloat(MealTime.minutesInDay))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                Text("12 AM"); Spacer(minLength: 0); Text("6 AM"); Spacer(minLength: 0); Text("12 PM")
                Spacer(minLength: 0); Text("6 PM"); Spacer(minLength: 0); Text("12 AM")
            }
            .font(.cave(.caption2)).foregroundStyle(Color.secondary)
            .accessibilityHidden(true)
            Text(gaps.isEmpty ? "Every time of day has a meal."
                 : "No meal: \(gaps.map(\.text).joined(separator: ", ")). Food logged then has no meal.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
                .accessibilityIdentifier("mealTimeGaps")
        }
        .padding(.vertical, 6)
    }

    /// A block that runs past midnight is drawn as two pieces.
    private func segments(_ time: MealTime) -> [Range<Int>] {
        time.crossesMidnight ? [time.start..<MealTime.minutesInDay, 0..<time.end] : [time.start..<time.end]
    }
}

/// Add or change one meal type: its name and (optionally) its time of day.
struct MealTypeEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: MealType?
    @State private var name: String
    @State private var hasTime: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var confirmingDelete = false
    /// Neighbors shortened to make room for this type's new time, saved along with it.
    @State private var adjusted: [String: MealType] = [:]
    @FocusState private var nameFocused: Bool

    init(type: MealType?) {
        original = type
        _name = State(initialValue: type?.name ?? "")
        _hasTime = State(initialValue: type.map { $0.time != nil } ?? true)
        let time = type?.time ?? MealTime(start: 12 * 60, end: 13 * 60)
        _start = State(initialValue: MealTime.date(time.start))
        _end = State(initialValue: MealTime.date(time.end))
    }

    private var settings: MealSettings { adjusted.values.reduce(store.mealSettings) { $0.saving($1) } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var time: MealTime? {
        hasTime ? MealTime(start: MealTime.minute(of: start), end: MealTime.minute(of: end)) : nil
    }
    private var problem: String? {
        if let other = settings.duplicate(named: trimmedName, excluding: original?.id), !trimmedName.isEmpty {
            return "You already have \(other.name)."
        }
        guard let time else { return nil }
        if !time.isValid { return "Start and end can’t be the same time." }
        if let other = settings.conflict(with: time, excluding: original?.id), let otherTime = other.time {
            return "Overlaps \(other.name) (\(otherTime.text)). Meal times can’t overlap."
        }
        return nil
    }
    private var canSave: Bool { !trimmedName.isEmpty && problem == nil }
    /// The overlapping neighbor and the shorter time that would make room, when that's possible.
    private var neighborFix: (type: MealType, time: MealTime)? {
        guard let time, time.isValid, let other = settings.conflict(with: time, excluding: original?.id),
              let trimmed = settings.trimmedTime(of: other, avoiding: time) else { return nil }
        return (other, trimmed)
    }

    var body: some View {
        NavigationStack {
            HapticForm {
                Section("Name") {
                    TextField("e.g. Morning Snack", text: $name)
                        .focused($nameFocused)
                        .accessibilityIdentifier("mealTypeName")
                        .keyboardInputArea()
                }
                Section {
                    Toggle("Set time", isOn: $hasTime.animation())
                        .accessibilityIdentifier("mealTypeHasTime")
                    if hasTime {
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("mealTypeStart")
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("mealTypeEnd")
                    }
                } footer: {
                    Group {
                        if let problem {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(problem).foregroundStyle(.red)
                                    .accessibilityIdentifier("mealTypeFooter")
                                if let fix = neighborFix {
                                    Button {
                                        var shortened = fix.type
                                        shortened.time = fix.time
                                        adjusted[shortened.id] = shortened
                                    } label: {
                                        Text("Shorten \(fix.type.name) to \(fix.time.text)")
                                            .font(.cave(.caption).weight(.semibold))
                                            .foregroundStyle(Color.caveOrange)
                                            .frame(minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .hapticButtonStyle(.borderless)
                                    .accessibilityIdentifier("shortenMealType")
                                }
                            }
                        } else if let time, time.isValid {
                            Text((settings.byTime
                                 ? "Food logged from \(MealTime.text(time.start)) to \(MealTime.text(time.end)) goes here\(time.crossesMidnight ? " (runs past midnight)" : "")."
                                 : "Times are used when Set meal by time of day is on.")
                                 + adjusted.values.sorted { $0.name < $1.name }.map { " Saving also changes \($0.name) to \($0.time?.text ?? "no set time")." }.joined())
                                .accessibilityIdentifier("mealTypeFooter")
                        } else {
                            Text("No set time: pick this meal when adding food, or long-press logged food to move it here.")
                                .accessibilityIdentifier("mealTypeFooter")
                        }
                    }
                    .font(.cave(.caption2))
                }
                if let original {
                    Section {
                        Button("Delete Meal Type", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("deleteMealType")
                    } footer: {
                        if store.mealTypeInUse(original.id) {
                            Text("Food already logged as \(original.name) keeps that label.").font(.cave(.caption2))
                        }
                    }
                }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle(original == nil ? "New Meal Type" : "Edit Meal Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .hapticButtonStyle(.automatic).hapticFeel(.success)
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveMealType")
                }
            }
            // A different time needs its own room; any shortened neighbors are worked out again.
            .onChange(of: start) { _, _ in adjusted = [:] }
            .onChange(of: end) { _, _ in adjusted = [:] }
            .onChange(of: hasTime) { _, _ in adjusted = [:] }
            .onChange(of: name) { _, value in
                if value.count > MealType.maxNameLength { name = String(value.prefix(MealType.maxNameLength)) }
            }
            .confirmationDialog("Delete \(original?.name ?? "meal type")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Haptics.play(.warning)
                    delete()
                }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: {
                if let original, store.mealTypeInUse(original.id) {
                    Text("Food already logged as \(original.name) keeps that label. New food can’t be added to it.")
                }
            }
            .task {
                guard original == nil else { return }
                // A new type starts in the first part of the day no meal covers, or without a time if none is free.
                if let gap = settings.uncoveredTimes.first {
                    start = MealTime.date(gap.start); end = MealTime.date(gap.end)
                } else if settings.visibleTypes.contains(where: { $0.time != nil }) {
                    hasTime = false
                }
                try? await Task.sleep(for: .milliseconds(300))
                nameFocused = true
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard canSave else { return }
        var type = original ?? MealType(name: trimmedName)
        type.name = trimmedName
        type.time = time
        guard store.saveMealSettings(settings.saving(type)) else { return }
        UsageStats.shared.event("mealTypes.edit", ["action": original == nil ? "add" : "change", "time": String(time != nil),
                                                   "shortened": String(!adjusted.isEmpty)])
        dismiss()
    }

    private func delete() {
        guard let original else { return }
        guard store.saveMealSettings(settings.removing(original.id, inUse: store.mealTypeInUse(original.id))) else { return }
        UsageStats.shared.event("mealTypes.edit", ["action": "delete"])
        dismiss()
    }
}
