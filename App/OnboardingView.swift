import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step = 0
    @State private var resultBackStep = 4
    @State private var gender: PlanGender?
    @State private var age = ""
    @State private var height = ""
    @State private var inches = ""
    @State private var weight = ""
    @State private var goalWeight = ""
    @State private var activity: PlanActivity?
    @State private var intent = PlanIntent.lose
    @State private var pace = 0.25
    @State private var unit = WeightUnit.pounds
    @State private var loaded = false
    @State private var initializedUnit = false
    @State private var clinicianSupport = false
    @State private var calorieGoal = ""
    @State private var trackWeight = true
    @State private var showingManual = false
    @State private var saving = false
    @State private var error: String?
    @FocusState private var field: String?
    var isRevising = false

    private var parsedAge: Int? {
        guard let value = WeightUnit.parse(age), (1...120).contains(value), value.rounded() == value else { return nil }
        return Int(value)
    }
    private var parsedHeight: Double? {
        guard let h = WeightUnit.parse(height) else { return nil }
        if unit == .kilograms { return h }
        guard let i = WeightUnit.parse(inches.isEmpty ? "0" : inches), i < 12 else { return nil }
        return (h * 12 + i) * 2.54
    }
    private var input: CaloriePlanInput? {
        guard let gender, let age = parsedAge, let cm = parsedHeight,
              let current = WeightUnit.parse(weight), let activity else { return nil }
        let target = intent == .maintain ? current : WeightUnit.parse(goalWeight)
        guard let target else { return nil }
        return CaloriePlanInput(gender: gender, age: age, heightCM: cm, weightKG: unit.kilograms(current),
                                goalKG: unit.kilograms(target), activity: activity, intent: intent, weeklyLossKG: pace)
    }
    private var estimate: CaloriePlanEstimate? { input.flatMap { CaloriePlanner.estimate($0, clinicianSupport: clinicianSupport) } }
    private var manualReason: String? {
        if clinicianSupport { return "A clinician can help set a target that fits your needs. You can still log food here." }
        if let age = parsedAge, !(18...80).contains(age) { return "This estimate is for adults 18–80. Use a target from your clinician instead." }
        if gender?.coefficient == nil { return "This equation uses female or male reference values. You can set your own target instead." }
        guard let input else { return "Check your details to build a plan." }
        return CaloriePlanner.validationMessage(input, clinicianSupport: clinicianSupport)
            ?? (estimate == nil ? "This estimate is outside the calculator’s range. Use a clinician’s target instead." : nil)
    }
    private var validStep: Bool {
        switch step {
        case 1: return gender != nil && parsedAge != nil
        case 2: return parsedHeight.map { (90...260).contains($0) } == true && WeightUnit.parse(weight).map { (20...400).contains(unit.kilograms($0)) } == true
        case 3: return activity != nil
        case 4: return intent == .maintain || WeightUnit.parse(goalWeight).map { (20...400).contains(unit.kilograms($0)) } == true
        case 5: return estimate != nil && WeightUnit.parse(calorieGoal).map { $0 >= (gender?.minimumCalories ?? 1500) && $0 <= 6000 } == true
        default: return true
        }
    }
    private var title: String {
        if step == 5 && estimate == nil { return "Start your way" }
        return ["", "A little about you", "Your starting point", "Your usual day", "Your goal. Your pace.", "Your starting target"][step]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        if step == 0 { welcome }
                        else {
                            ProgressView(value: Double(step), total: 5).accessibilityLabel("Step \(step) of 5")
                            Text(title).font(.cave(.largeTitle)).accessibilityAddTraits(.isHeader)
                            stepContent
                        }
                        if let error { Text(error).foregroundStyle(.red).font(.cave(.footnote)) }
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    // Large accessibility text needs the full viewport for each question.
                    if dynamicTypeSize.isAccessibilitySize { footer }
                }
            }.caveScreenBackground()
            .scrollDismissesKeyboard(.interactively)
            .id(step)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize { footer }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 0 {
                        Button { changeStep(step == 5 ? resultBackStep : step - 1) } label: { CaveIcon(.chevronLeft, size: 20).frame(width: 44, height: 44) }
                            .accessibilityLabel("Back").accessibilityIdentifier("onboardingBack")
                    } else if isRevising { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRevising && step > 0 { Button("Cancel") { dismiss() } }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { field = nil } }
            }
            .sheet(isPresented: $showingManual) {
                SetupView(goal: isRevising ? store.profile?.dailyGoal : nil, isAdjustingGoal: true, onSaved: { dismiss() })
            }
            .onAppear { loadSavedPlan() }
            .onChange(of: unit) { old, new in
                if initializedUnit { convertUnits(from: old, to: new) }
                initializedUnit = true
            }
        }
    }
    private var welcome: some View {
        VStack(spacing: 22) {
            Image("SetupAppIcon").resizable().scaledToFit().frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
            Text("You Eat.\nApp Track.\nWeight Drop.").font(.cave(.largeTitle)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Gender").font(.cave(.headline))
                ForEach(PlanGender.choices) { value in option(value.rawValue, selected: gender == value, id: "gender-\(value.id)") { gender = value } }
                Text("The equation uses female/male reference values. If neither fits, you can set your own goal.")
                    .font(.cave(.caption)).foregroundStyle(.secondary)
                numberField("Age", text: $age, suffix: "years", id: "planAge", decimal: false)
                switchRow("I need a clinician-led plan", isOn: $clinicianSupport, id: "planClinician").font(.cave(.subheadline))
                Text("Choose this if pregnant, breastfeeding, or managing an eating disorder or medical nutrition needs.")
                    .font(.cave(.caption)).foregroundStyle(.secondary)
            }
        case 2:
            unitPicker
            if unit == .pounds {
                // Only feet carries the "Height" label, so align the boxes by their bottoms.
                HStack(alignment: .bottom, spacing: 12) {
                    numberField("Height", text: $height, suffix: "ft", id: "planHeight", decimal: false)
                    numberField("", text: $inches, suffix: "in", id: "planInches")
                }
            } else { numberField("Height", text: $height, suffix: "cm", id: "planHeight") }
            numberField("Current weight", text: $weight, suffix: unit.rawValue, id: "planWeight")
                Text("Your answers stay on this device.").font(.cave(.footnote)).foregroundStyle(.secondary)
        case 3:
            Text("Include work, walking, and exercise.").foregroundStyle(.secondary)
            ForEach(PlanActivity.allCases) { value in
                option(value.rawValue, detail: value.detail, selected: activity == value, id: "activity-\(value.id)") { activity = value }
            }
        case 4:
            Picker("Goal", selection: $intent) { ForEach(PlanIntent.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("planIntent")
            if intent == .lose {
                numberField("Goal weight", text: $goalWeight, suffix: unit.rawValue, id: "planGoalWeight")
                ForEach([0.25, 0.5, 0.75], id: \.self) { speed in
                    option(paceTitle(speed), detail: speed == 0.25 ? "An easier place to start" : speed == 0.5 ? "A moderate pace" : "A larger daily change", selected: pace == speed, id: "pace-\(speed)") { pace = speed }
                }
                Text("We’ll keep the target within sensible limits. Your actual pace may be slower.").font(.cave(.footnote)).foregroundStyle(.secondary)
            } else { Text("We’ll estimate a target to keep your weight steady.").foregroundStyle(.secondary) }
        case 5:
            if let estimate {
                VStack(spacing: 10) {
                    Text("Daily calories").foregroundStyle(.secondary)
                    TextField("Calories", text: $calorieGoal).keyboardType(.numberPad).focused($field, equals: "planCalories")
                        .font(.custom("Schoolbell-Regular", size: 58, relativeTo: .largeTitle)).multilineTextAlignment(.center)
                        .accessibilityLabel("Daily calorie target").accessibilityIdentifier("planCalories")
                    Text("Tap to adjust").font(.cave(.caption)).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity).background(Color.caveOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                if !validStep {
                    Text("Enter \(Int(gender?.minimumCalories ?? 1500).formatted())–6,000 calories, or go back to change your plan.")
                        .font(.cave(.footnote)).foregroundStyle(.red).accessibilityIdentifier("planTargetValidation")
                }
                if estimate.paceLimited { Text("We eased the pace to keep your starting target higher.").font(.cave(.subheadline)) }
                Text("An estimate, not a promise. Track for a few weeks and adjust with your progress.").font(.cave(.subheadline)).foregroundStyle(.secondary)
                switchRow("Track my weight", isOn: $trackWeight, id: "planTrackWeight")
                Text("Adds your starting weight if today is empty. Apple Health stays optional.").font(.cave(.caption)).foregroundStyle(.secondary)
                DisclosureGroup("How we worked it out") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Estimated maintenance: \(estimate.maintenance.calorieText) calories. We use your age, height, weight, activity, and the Mifflin–St Jeor equation, then allow a modest deficit for weight loss. Your goal weight sets the direction, not a deadline.")
                        Text("Automatic targets use at least \(Int(gender?.minimumCalories ?? 1500)) calories and limit the deficit to 25% or 750 calories, whichever is smaller. These limits don’t guarantee a suitable diet for everyone.")
                        Link("Calorie equation research", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                        Link("NIH weight-planning guidance", destination: URL(string: "https://www.niddk.nih.gov/bwp")!)
                        Link("CDC: gradual weight loss", destination: URL(string: "https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html")!)
                    }.font(.cave(.footnote)).padding(.top, 8)
                }
            } else {
                CaveIcon(.person, size: 44).foregroundStyle(Color.caveOrange)
                Text(manualReason ?? "Use a target that fits your needs.").font(.cave(.title3))
                Text("You can use a clinician’s target or start without a calorie goal.").foregroundStyle(.secondary)
            }
        default: EmptyView()
        }
    }
    private var unitPicker: some View {
        Picker("Units", selection: $unit) { Text("lb / ft").tag(WeightUnit.pounds); Text("kg / cm").tag(WeightUnit.kilograms) }
            .pickerStyle(.segmented).accessibilityIdentifier("planUnits")
    }
    private var footer: some View {
        VStack(spacing: 4) {
            if step == 5 && estimate == nil {
                Button { showingManual = true } label: {
                    Text("Set my own goal").multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("manualSetup")
                Button("Start without a goal") { finishWithoutGoal() }.frame(minHeight: 44).accessibilityIdentifier("skipGoal")
            } else {
                Button { advance() } label: {
                    HStack(spacing: 10) {
                        Text(step == 0 ? "Me Build Plan" : step == 5 ? (isRevising ? "Save my plan" : "Let’s go") : "Continue")
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if step == 0 { CaveIcon(.arrowRight, size: 22).accessibilityHidden(true) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(!validStep || saving).accessibilityIdentifier("onboardingContinue")
                if step == 0 && !isRevising {
                    Button("Just start tracking") { finishWithoutGoal() }.frame(minHeight: 44).accessibilityIdentifier("skipGoal")
                }
            }
        }.font(.cave(.body)).padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 560).frame(maxWidth: .infinity).background(.regularMaterial)
    }
    private func numberField(_ label: String, text: Binding<String>, suffix: String, id: String, decimal: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { Text(label).font(.cave(.subheadline)) }
            HStack {
                TextField("0", text: text).keyboardType(decimal ? .decimalPad : .numberPad).focused($field, equals: id)
                    .font(.cave(.title)).accessibilityLabel(label.isEmpty ? "Height in inches" : label).accessibilityIdentifier(id)
                Text(suffix).foregroundStyle(.secondary)
            }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    /// Scroll views swallow quick taps on a bare switch, so the whole row flips it.
    private func switchRow(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Toggle(title, isOn: isOn).labelsHidden().allowsHitTesting(false)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(title, isOn: isOn) }
            .accessibilityIdentifier(id)
    }
    private func option(_ title: String, detail: String? = nil, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(title); if let detail { Text(detail).font(.cave(.caption)).foregroundStyle(.secondary) } }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.caveOrange : .secondary)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(selected ? Color.caveOrange.opacity(0.1) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
    private func paceTitle(_ kg: Double) -> String {
        let precision = unit == .kilograms ? 2 : 1
        return "\(unit.display(kg).formatted(.number.precision(.fractionLength(0...precision)))) \(unit.rawValue) per week"
    }
    private func changeStep(_ next: Int) {
        field = nil; error = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
    }
    private func advance() {
        guard validStep else { return }
        if step == 5 { save(); return }
        if step == 1 && (clinicianSupport || gender?.coefficient == nil || !(18...80).contains(parsedAge ?? 0)) {
            resultBackStep = 1; error = nil; changeStep(5); return
        }
        if step == 4 { resultBackStep = 4; calorieGoal = estimate.map { String(Int($0.calories)) } ?? "" }
        changeStep(step + 1)
    }
    private func finishWithoutGoal() {
        if store.saveGoal(nil) { dismiss() }
    }
    private func save() {
        guard !saving, let input, let goal = WeightUnit.parse(calorieGoal), validStep else { return }
        saving = true
        // Save the local plan first. If diary persistence fails, setup stays open for retry.
        guard weights.saveCaloriePlan(SavedCaloriePlan(input: input, calorieGoal: goal), unit: unit, trackWeight: trackWeight) else {
            error = weights.error; saving = false; return
        }
        if store.saveGoal(goal) { dismiss() }
        saving = false
    }
    private func loadSavedPlan() {
        guard !loaded else { return }; loaded = true
        unit = weights.unit
        initializedUnit = unit == .pounds
        guard isRevising, let saved = weights.caloriePlan else { return }
        let p = saved.input
        gender = p.gender; age = String(p.age); activity = p.activity; intent = p.intent; pace = p.weeklyLossKG
        weight = unit.editingText(weights.records.first?.kilograms ?? p.weightKG)
        goalWeight = unit.editingText(p.goalKG)
        setHeight(p.heightCM, unit: unit)
        trackWeight = weights.tracking
    }
    private func setHeight(_ cm: Double, unit: WeightUnit) {
        if unit == .kilograms { height = cm.formatted(.number.grouping(.never).precision(.fractionLength(0...1))); inches = "" }
        else {
            guard let total = Int(exactly: (cm / 2.54).rounded()), total >= 0 else {
                height = ""; inches = ""; error = "Enter your height again."; return
            }
            height = String(total / 12); inches = String(total % 12)
        }
    }
    private func convertUnits(from old: WeightUnit, to new: WeightUnit) {
        if let current = WeightUnit.parse(weight) { weight = new.editingText(old.kilograms(current)) }
        if let target = WeightUnit.parse(goalWeight) { goalWeight = new.editingText(old.kilograms(target)) }
        if let h = WeightUnit.parse(height) {
            let cm = old == .kilograms ? h : (h * 12 + (WeightUnit.parse(inches) ?? 0)) * 2.54
            setHeight(cm, unit: new)
        }
    }
}
