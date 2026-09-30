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
    @State private var age = 40
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
    @State private var trackMacros = true
    @State private var showingManual = false
    @State private var confirmingClear = false
    @State private var confirmingSkip = false
    /// "Just start tracking" still asks the tracking step, then finishes without a goal.
    @State private var skippingPlan = false
    /// How far the welcome intro has played: 1–3 headline lines, 4 the logo, 5 the buttons.
    @State private var introStage = 0
    @State private var saving = false
    @State private var error: String?
    @FocusState private var field: String?
    var isRevising = false
    var isPreview = false
    var onCompleted: () -> Void = {}

    private var parsedHeight: Double? {
        guard let h = WeightUnit.parse(height) else { return nil }
        if unit == .kilograms { return h }
        guard let i = WeightUnit.parse(inches.isEmpty ? "0" : inches), i < 12 else { return nil }
        return (h * 12 + i) * 2.54
    }
    private var input: CaloriePlanInput? {
        guard let gender, let cm = parsedHeight,
              let current = WeightUnit.parse(weight), let activity else { return nil }
        let target = intent == .maintain ? current : WeightUnit.parse(goalWeight)
        guard let target else { return nil }
        return CaloriePlanInput(gender: gender, age: age, heightCM: cm, weightKG: unit.kilograms(current),
                                goalKG: unit.kilograms(target), activity: activity, intent: intent, weeklyLossKG: pace)
    }
    private var estimate: CaloriePlanEstimate? { input.flatMap { CaloriePlanner.estimate($0, clinicianSupport: clinicianSupport) } }
    private var manualReason: String? {
        if clinicianSupport { return "A clinician can help set a target that fits your needs. You can still log food here." }
        if !(18...80).contains(age) { return "This estimate is for adults 18–80. Use a target from your clinician instead." }
        if gender?.coefficient == nil { return "This equation uses female or male reference values. You can set your own target instead." }
        guard let input else { return "Check your details to build a plan." }
        return CaloriePlanner.validationMessage(input, clinicianSupport: clinicianSupport)
            ?? (estimate == nil ? "This estimate is outside the calculator’s range. Use a clinician’s target instead." : nil)
    }
    private var validStep: Bool {
        switch step {
        case 1: return gender != nil
        case 2: return parsedHeight.map { (90...260).contains($0) } == true && WeightUnit.parse(weight).map { (20...400).contains(unit.kilograms($0)) } == true
        case 3: return activity != nil
        case 4: return intent == .maintain || WeightUnit.parse(goalWeight).map { (20...400).contains(unit.kilograms($0)) } == true
        case 6: return estimate != nil && parsedCalorieGoal.map { $0 >= (gender?.minimumCalories ?? 1500) && $0 <= 6000 } == true
        default: return true
        }
    }
    private var title: String {
        if step == 6 && estimate == nil { return "Start your way" }
        return ["", "Me Info", "Measurements", "Usual Week", "Set Goal", "What do you want to track?", "Your target"][step]
    }
    /// The target shows grouped ("2,050") and is typed on a number pad, so only its digits count;
    /// grouping separators differ by region.
    private var parsedCalorieGoal: Double? {
        let digits = calorieGoal.compactMap(\.wholeNumberValue)
        guard (1...5).contains(digits.count) else { return nil }
        return Double(digits.reduce(0) { $0 * 10 + $1 })
    }
    private func formattedCalories(_ value: Double) -> String { Int(value).formatted() }
    /// Revisions skip the tracking step (About You owns those switches), so they have one fewer step.
    private var stepCount: Int { isRevising ? 5 : 6 }
    private var stepNumber: Int { isRevising && step == 6 ? 5 : step }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        if step == 0 { welcome }
                        else {
                            if !skippingPlan {
                                ProgressView(value: Double(stepNumber), total: Double(stepCount))
                                    .accessibilityLabel("Step \(stepNumber) of \(stepCount)")
                            }
                            if step == 4 { goalHeader } else { stepTitle }
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
                        Button { goBack() } label: { CaveIcon(.chevronLeft, size: 20).frame(width: 44, height: 44) }
                            .hapticButtonStyle(.automatic).accessibilityLabel("Back").accessibilityIdentifier("onboardingBack")
                    } else if isRevising { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isPreview {
                        Button("Close Preview") { dismiss() }
                            .hapticButtonStyle(.automatic).accessibilityIdentifier("closeOnboardingPreview")
                    } else if isRevising && step > 0 { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { field = nil }.hapticButtonStyle(.automatic) }
            }
            .sheet(isPresented: $showingManual) {
                SetupView(goal: isRevising ? store.profile?.dailyGoal : nil, isAdjustingGoal: true,
                          saveAction: { saveTrackingAndGoal($0) }, onSaved: { complete() })
            }
            .alert("Clear saved answers?", isPresented: $confirmingClear) {
                // Alert buttons may skip the haptic button style, so they play their own feel.
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
                Button("Clear answers", role: .destructive) { Haptics.play(.warning); clearSavedAnswers() }.hapticFeel(.none)
            } message: {
                Text("Removes your saved age, gender, height, and plan answers. Your calorie goal and weigh-ins stay.")
            }
            .alert("Skip plan?", isPresented: $confirmingSkip) {
                Button("Yes, skip plan") { Haptics.play(.tap); skipPlan() }.hapticFeel(.none)
                Button("No, me build plan") { Haptics.play(.tap); advance() }.hapticFeel(.none)
            } message: {
                Text("Cave Cals help you pick daily calorie target to reach your goal. Take less than one minute.")
            }
            .onAppear { loadSavedPlan() }
            .onChange(of: unit) { old, new in
                // Converting fills the height boxes, which must not trigger the typing jumps below.
                if initializedUnit { field = nil; convertUnits(from: old, to: new) }
                initializedUnit = true
            }
            .onChange(of: field) { old, _ in
                if old == "planCalories", let goal = parsedCalorieGoal { calorieGoal = formattedCalories(goal) }
            }
            // Feet and inches only accept real values, and a finished box moves on to the next one.
            .onChange(of: height) { old, new in
                guard unit == .pounds else { return }
                let clean = ImperialHeightInput.feet(new, previous: old)
                if clean != new { height = clean }
                if field == "planHeight", !clean.isEmpty, clean != old { field = "planInches" }
            }
            .onChange(of: weight) { _, new in
                let clean = WeightInput.oneDecimal(new)
                if clean != new { weight = clean }
            }
            .onChange(of: goalWeight) { _, new in
                let clean = WeightInput.oneDecimal(new)
                if clean != new { goalWeight = clean }
            }
            .onChange(of: inches) { old, new in
                guard unit == .pounds else { return }
                let clean = ImperialHeightInput.inches(new, previous: old)
                if clean != new { inches = clean }
                if field == "planInches", ImperialHeightInput.inchesComplete(clean), clean != old { field = "planWeight" }
            }
        }
    }
    private static let introDone = 5
    private var welcome: some View {
        VStack(spacing: 28) {
            // All three lines share the largest size that fits on one line each; none wraps or truncates.
            ViewThatFits(in: .horizontal) {
                headline(size: 60); headline(size: 50); headline(size: 42); headline(size: 34, fitted: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You Eat. App Track. Weight Drop.").accessibilityAddTraits(.isHeader)
            Image("WelcomeLogo").resizable().scaledToFit().frame(height: 190)
                .offset(y: introOffset(stage: 4, by: 480)).opacity(introStage >= 4 ? 1 : 0)
                .accessibilityHidden(true)
        }.padding(.top, 36).frame(maxWidth: .infinity)
            .task { await playIntro() }
    }
    private func headline(size: CGFloat, fitted: Bool = true) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(["You Eat.", "App Track.", "Weight Drop."].enumerated()), id: \.offset) { index, line in
                let text = Text(line).font(.custom("Schoolbell-Regular", size: size, relativeTo: .largeTitle)).lineLimit(1)
                Group { if fitted { text.fixedSize() } else { text.minimumScaleFactor(0.4) } }
                    // Lines alternate sides: left, right, left.
                    .offset(x: introOffset(stage: index + 1, by: index == 1 ? 600 : -600))
                    .opacity(introStage > index ? 1 : 0)
            }
        }
    }
    /// Reduce Motion fades the intro in place instead of sliding it.
    private func introOffset(stage: Int, by distance: CGFloat) -> CGFloat {
        introStage >= stage || reduceMotion ? 0 : distance
    }
    /// Plays once per setup: the lines slide in, the logo springs up and settles, then the buttons rise.
    private func playIntro() async {
        guard introStage < Self.introDone else { return }
        if isRevising || reduceMotion || ProcessInfo.processInfo.arguments.contains("--uitesting") {
            withAnimation(reduceMotion ? .easeOut(duration: 0.35) : nil) { introStage = Self.introDone }
            return
        }
        let line = Animation.spring(response: 0.5, dampingFraction: 0.86)
        let beats: [(delay: Double, animation: Animation)] = [
            (0.25, line), (0.3, line), (0.3, line),
            // Overshoots upward a little, then settles down into place.
            (0.35, .spring(response: 0.6, dampingFraction: 0.62)),
            (0.45, .spring(response: 0.5, dampingFraction: 0.9)),
        ]
        for (index, beat) in beats.enumerated() {
            try? await Task.sleep(for: .seconds(beat.delay))
            guard !Task.isCancelled else { introStage = Self.introDone; return }
            withAnimation(beat.animation) { introStage = index + 1 }
        }
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Type").font(.cave(.headline))
                genderChoices
                Text("Age").font(.cave(.headline)).padding(.top, 8)
                AgeDial(age: $age).accessibilityIdentifier("planAge")
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
                    numberField("", text: $inches, suffix: "in", id: "planInches", decimal: false)
                }
            } else { numberField("Height", text: $height, suffix: "cm", id: "planHeight") }
            numberField("Current weight", text: $weight, suffix: unit.rawValue, id: "planWeight", placeholder: weightPlaceholder)
                Text("Your answers stay on this device.").font(.cave(.footnote)).foregroundStyle(.secondary)
        case 3:
            ForEach(PlanActivity.allCases) { value in
                option(value.rawValue, detail: value.detail, selected: activity == value, id: "activity-\(value.id)") { activity = value }
            }
        case 4:
            if intent == .lose {
                numberField("Goal weight", text: $goalWeight, suffix: unit.rawValue, id: "planGoalWeight", placeholder: weightPlaceholder, note: currentWeightNote)
                Text("Rate").font(.cave(.subheadline)).padding(.bottom, -8)
                ForEach([0.25, 0.5, 0.75], id: \.self) { speed in
                    option(paceTitle(speed), detail: speed == 0.25 ? "An easier place to start" : speed == 0.5 ? "A moderate pace" : "A larger daily change", selected: pace == speed, id: "pace-\(speed)") { pace = speed }
                }
                Text("We’ll keep the target within sensible limits. Your actual pace may be slower.").font(.cave(.footnote)).foregroundStyle(.secondary)
            } else { Text("We’ll estimate a target to keep your weight steady.").foregroundStyle(.secondary) }
        case 5:
            Text("Calories are always included. Pick what else works for you.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                switchRow("Track my weight", isOn: $trackWeight, id: "planTrackWeight")
                Divider()
                switchRow("Track macros", isOn: $trackMacros, id: "planTrackMacros")
            }.padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Text("You can change these anytime in About You.").font(.cave(.footnote)).foregroundStyle(.secondary)
        case 6:
            if let estimate {
                VStack(spacing: 2) {
                    Text("Daily calories").foregroundStyle(.secondary)
                    TextField("Calories", text: $calorieGoal).keyboardType(.numberPad).focused($field, equals: "planCalories")
                        .font(.custom("Schoolbell-Regular", size: 58, relativeTo: .largeTitle)).multilineTextAlignment(.center)
                        .accessibilityLabel("Daily calorie target").accessibilityIdentifier("planCalories")
                        .selectValueOnFocus(identifier: "planCalories")
                    Text("Tap to adjust").font(.cave(.caption)).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 14)
                    .frame(maxWidth: .infinity).background(Color.caveOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                    // The whole card opens the number with it selected, so typing replaces it.
                    .contentShape(RoundedRectangle(cornerRadius: 22))
                    .onTapGesture { field = "planCalories" }
                if !validStep {
                    Text("Enter \(Int(gender?.minimumCalories ?? 1500).formatted())–6,000 calories, or go back to change your plan.")
                        .font(.cave(.footnote)).foregroundStyle(.red).accessibilityIdentifier("planTargetValidation")
                }
                if estimate.paceLimited { Text("We eased the pace to keep your starting target higher.").font(.cave(.subheadline)) }
                Text("An estimate, not a promise. Track for a few weeks and adjust with your progress.").font(.cave(.subheadline)).foregroundStyle(.secondary)
                if isRevising {
                    switchRow("Track my weight", isOn: $trackWeight, id: "planTrackWeight")
                }
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
    private var stepTitle: some View {
        Text(title).font(.cave(.largeTitle)).accessibilityAddTraits(.isHeader)
    }
    /// Lose/Maintain sits beside the title when it fits, leaving the step more room; otherwise it goes below.
    private var goalHeader: some View {
        let picker = Picker("Goal", selection: $intent) { ForEach(PlanIntent.allCases) { Text($0.title).tag($0) } }
            .pickerStyle(.segmented).hapticSelection(on: intent).accessibilityIdentifier("planIntent")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                stepTitle
                Spacer(minLength: 0)
                picker.fixedSize()
            }
            VStack(alignment: .leading, spacing: 22) { stepTitle; picker }
        }
    }
    /// Picture cards side by side; large text stacks them so the labels stay readable.
    private var genderChoices: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(PlanGender.choices) { value in
                let selected = gender == value
                Button { gender = value } label: {
                    VStack(spacing: 8) {
                        Image(artwork(value)).resizable().scaledToFit().frame(height: 76).accessibilityHidden(true)
                        Text(value.title).foregroundStyle(Color.primary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? Color.caveOrange.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.caveOrange : .clear, lineWidth: 2) }
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }.hapticButtonStyle(.plain).hapticFeel(.selection)
                    .accessibilityLabel(value == .undisclosed ? value.rawValue : value.title)
                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("gender-\(value.id)")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func artwork(_ gender: PlanGender) -> String {
        switch gender { case .male: return "SetupMan"; case .female: return "SetupWoman"; default: return "SetupPreferNotToSay" }
    }
    private var unitPicker: some View {
        Picker("Units", selection: $unit) { Text("lb / ft").tag(WeightUnit.pounds); Text("kg / cm").tag(WeightUnit.kilograms) }
            .pickerStyle(.segmented).hapticSelection(on: unit).accessibilityIdentifier("planUnits")
    }
    private var footer: some View {
        VStack(spacing: 4) {
            if step == 6 && estimate == nil {
                Button { showingManual = true } label: {
                    Text("Set my own goal").multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                }.hapticButtonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("manualSetup")
                Button("Start without a goal") { finishWithoutGoal() }.frame(minHeight: 44).accessibilityIdentifier("skipGoal")
            } else {
                Button { advance() } label: {
                    HStack(spacing: 10) {
                        Text(step == 0 ? "Me Build Plan" : step == 6 ? (isRevising ? "Save my plan" : "Let’s go") : skippingPlan ? "Let’s go" : "Continue")
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if step == 0 { CaveIcon(.arrowRight, size: 22).accessibilityHidden(true) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.hapticButtonStyle(.borderedProminent).hapticFeel(step == 6 || skippingPlan ? .success : .tap).disabled(!validStep || saving).accessibilityIdentifier("onboardingContinue")
                if step == 0 && !isRevising {
                    Button("Just start tracking") { confirmingSkip = true }.frame(minHeight: 44).accessibilityIdentifier("skipGoal")
                }
                if step == 0 && isRevising && weights.caloriePlan != nil {
                    Button("Clear my saved answers", role: .destructive) { confirmingClear = true }
                        .foregroundStyle(.red).frame(minHeight: 44).accessibilityIdentifier("clearSavedAnswers")
                }
            }
        }.font(.cave(.body)).padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 560).frame(maxWidth: .infinity).background(.regularMaterial)
            // The welcome intro brings the buttons and their panel up last.
            .offset(y: step == 0 ? introOffset(stage: Self.introDone, by: 360) : 0)
            .opacity(step == 0 && introStage < Self.introDone ? 0 : 1)
    }
    /// Today's weight beside the goal-weight label, for reference.
    private var currentWeightNote: String? {
        WeightUnit.parse(weight).map { "Current: \($0.formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)" }
    }
    /// "0.0" (or "0,0") hints that weights take one decimal place.
    private var weightPlaceholder: String { 0.0.formatted(.number.precision(.fractionLength(1))) }
    private func numberField(_ label: String, text: Binding<String>, suffix: String, id: String, decimal: Bool = true,
                             placeholder: String = "0", note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                    Spacer(minLength: 8)
                    if let note { Text(note).foregroundStyle(Color.caveOrange).accessibilityIdentifier("\(id)Note") }
                }.font(.cave(.subheadline))
            }
            HStack {
                TextField(placeholder, text: text).keyboardType(decimal ? .decimalPad : .numberPad).focused($field, equals: id)
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
        }.hapticButtonStyle(.plain).hapticFeel(.selection)
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
        }.hapticButtonStyle(.plain).hapticFeel(.selection).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
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
        if step == 6 { save(); return }
        if step == 5 {
            if skippingPlan { finishWithoutGoal() } else { changeStep(6) }
            return
        }
        if step == 1 && (clinicianSupport || gender?.coefficient == nil || !(18...80).contains(age)) {
            resultBackStep = 1; error = nil; changeStep(isRevising ? 6 : 5); return
        }
        if step == 4 {
            resultBackStep = 4; calorieGoal = estimate.map { formattedCalories($0.calories) } ?? ""
            changeStep(isRevising ? 6 : 5); return
        }
        changeStep(step + 1)
    }
    /// The tracking step sits just before the target, so manual-only results return through it.
    private func goBack() {
        switch step {
        case 6: changeStep(isRevising ? resultBackStep : 5)
        case 5 where skippingPlan: skippingPlan = false; changeStep(0)
        case 5: changeStep(resultBackStep)
        default: changeStep(step - 1)
        }
    }
    private func skipPlan() {
        skippingPlan = true; changeStep(5)
    }
    private func finishWithoutGoal() {
        if saveTrackingAndGoal(nil) { complete() }
    }
    private func complete() {
        if isRevising || isPreview { dismiss() }
        else { onCompleted() }
    }
    private func saveTrackingAndGoal(_ goal: Double?) -> Bool {
        if !isRevising && !weights.setTracking(trackWeight) {
            error = weights.error
            return false
        }
        let saved = store.saveGoal(goal, tracksMacros: isRevising ? nil : trackMacros)
        if !saved { error = store.error }
        return saved
    }
    private func save() {
        guard !saving, let input, let goal = parsedCalorieGoal, validStep else { return }
        saving = true
        // Save the local plan first. If diary persistence fails, setup stays open for retry.
        guard weights.saveCaloriePlan(SavedCaloriePlan(input: input, calorieGoal: goal), unit: unit, trackWeight: trackWeight) else {
            error = weights.error; saving = false; return
        }
        if store.saveGoal(goal, tracksMacros: isRevising ? nil : trackMacros) { complete() }
        else { error = store.error }
        saving = false
    }
    private func loadSavedPlan() {
        guard !loaded else { return }; loaded = true
        unit = weights.unit
        initializedUnit = unit == .pounds
        if isRevising { trackWeight = weights.tracking }
        guard isRevising, let saved = weights.caloriePlan else { return }
        let p = saved.input
        gender = p.gender; age = AgeDial.range.clamped(p.age); activity = p.activity; intent = p.intent; pace = p.weeklyLossKG
        weight = WeightInput.text(weights.records.first?.kilograms ?? p.weightKG, in: unit)
        goalWeight = WeightInput.text(p.goalKG, in: unit)
        setHeight(p.heightCM, unit: unit)
    }
    /// Starts the calculator fresh; the current calorie goal and weigh-ins are untouched.
    private func clearSavedAnswers() {
        guard weights.forgetCaloriePlan() else { error = weights.error; return }
        gender = nil; age = 40; height = ""; inches = ""; weight = ""; goalWeight = ""
        activity = nil; intent = .lose; pace = 0.25; clinicianSupport = false; calorieGoal = ""
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
        if let current = WeightUnit.parse(weight) { weight = WeightInput.text(old.kilograms(current), in: new) }
        if let target = WeightUnit.parse(goalWeight) { goalWeight = WeightInput.text(old.kilograms(target), in: new) }
        if let h = WeightUnit.parse(height) {
            let cm = old == .kilograms ? h : (h * 12 + (WeightUnit.parse(inches) ?? 0)) * 2.54
            setHeight(cm, unit: new)
        }
    }
}

/// A ruler of ages to swipe left or right; the number under the caret is the age.
private struct AgeDial: View {
    static let range = 13...100
    @Binding var age: Int
    @State private var centered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Numbers grow with Dynamic Type, so their slots and the dial do too.
    @ScaledMetric(relativeTo: .title) private var itemWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var dialHeight: CGFloat = 104

    var body: some View {
        GeometryReader { geometry in
            ruler
                // Insetting both sides to the middle makes the snapped (leading) number the centered one,
                // and lets the first and last ages reach the caret.
                .safeAreaPadding(.horizontal, max(0, (geometry.size.width - itemWidth) / 2))
                .onAppear { centered = age }
        }
        .frame(height: dialHeight)
        // Fades the outer numbers; applied outside the insets so it spans the whole dial.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                     .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .top) {
            CaveIcon(.chevronRight, size: 20).rotationEffect(.degrees(90))
                .foregroundStyle(Color.caveOrange).padding(.top, 6).accessibilityHidden(true)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: centered) { _, value in
            if let value, value != age { age = value }
        }
        .onChange(of: age) { _, value in
            if centered != value { centered = value }
        }
        .hapticSelection(on: age)
        // Past this size the numbers crowd each other out; VoiceOver still reads the value.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Age")
        .accessibilityValue("\(age) years")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(age + 1)
            case .decrement: select(age - 1)
            @unknown default: break
            }
        }
    }
    private var ruler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.range, id: \.self) { value in
                    let selected = value == age
                    VStack(spacing: 6) {
                        Capsule().fill(selected ? Color.caveOrange : Color.secondary.opacity(0.45))
                            .frame(width: 2, height: value % 5 == 0 ? 16 : 10)
                        Text("\(value)").font(.cave(.title)).lineLimit(1).fixedSize()
                            .foregroundStyle(selected ? Color.caveOrange : Color.secondary)
                            .scaleEffect(selected ? 1.2 : 0.8)
                    }
                    .frame(width: itemWidth).padding(.top, 30)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { select(value) }
                }
            }.scrollTargetLayout()
        }
        // The default limit stops a flick after about one screenful; let momentum carry and then snap.
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollPosition(id: $centered)
    }
    private func select(_ value: Int) {
        let value = Self.range.clamped(value)
        age = value
        withAnimation(reduceMotion ? nil : .snappy) { centered = value }
    }
}

private extension ClosedRange where Bound == Int {
    func clamped(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

/// Typing rules for the feet and inches boxes: only real heights, and each box knows when it's finished.
enum ImperialHeightInput {
    static let feetRange = 3...7
    /// One digit from 3 to 7. Typing over a value replaces it; any other digit is ignored.
    static func feet(_ typed: String, previous: String) -> String {
        if typed.isEmpty { return "" }
        if let digit = typed.last?.wholeNumberValue, feetRange.contains(digit) { return String(digit) }
        return isFeet(previous) ? previous : ""
    }
    /// 0 to 11. Typing past a finished value starts over with the new digit; a stray digit after "1" is ignored.
    static func inches(_ typed: String, previous: String) -> String {
        if typed.isEmpty || isInches(typed) { return typed }
        if previous != "1", let last = typed.last, isInches(String(last)) { return String(last) }
        return isInches(previous) ? previous : ""
    }
    /// Every value but "1" is finished; "1" may still become 10 or 11.
    static func inchesComplete(_ text: String) -> Bool { isInches(text) && text != "1" }
    private static func isFeet(_ text: String) -> Bool { text.isEmpty || Int(text).map { feetRange.contains($0) && text == String($0) } == true }
    private static func isInches(_ text: String) -> Bool { Int(text).map { (0...11).contains($0) && text == String($0) } == true }
}

/// Setup weights use one decimal place, like the rest of the app's weights.
enum WeightInput {
    /// Drops decimal digits typed past the first.
    static func oneDecimal(_ text: String, separator: String = Locale.current.decimalSeparator ?? ".") -> String {
        guard let mark = text.range(of: separator) else { return text }
        let fraction = text[mark.upperBound...]
        return fraction.count > 1 ? String(text[..<mark.upperBound]) + fraction.prefix(1) : text
    }
    /// Filled-in weights (saved plans, unit switches) are rounded rather than cut off.
    static func text(_ kilograms: Double, in unit: WeightUnit) -> String {
        unit.display(kilograms).formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}
