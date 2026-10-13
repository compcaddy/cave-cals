import SwiftUI

// MARK: New challenge

struct NewChallengeView: View {
    let clanId: String
    let clanRule: ClanRule
    let memberCount: Int
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ChallengeKind?
    @State private var basis = "logging"
    @State private var anyFood = false
    @State private var rule = ClanRule()
    @State private var length = 14
    @State private var weeks = 4
    @State private var openEnded = true
    @State private var streakMode = "everyone"
    @State private var streakPercent = 80
    @State private var teamTarget = 100
    @State private var saves = 1
    @State private var savesPeriod = "week"
    @State private var start = Date()
    @State private var busy = false
    @State private var message: String?
    @State private var paywall = false
    @State private var subscriptions = AISubscriptions()

    var body: some View {
        NavigationStack {
            Group {
                if let kind { form(kind) } else { picker }
            }
            .caveScreenBackground()
            .navigationTitle(kind?.title ?? "New challenge").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(kind == nil ? "Cancel" : "Back") { if kind == nil { dismiss() } else { kind = nil } }.hapticButtonStyle(.automatic)
                }
            }
            .navigationDestination(isPresented: $paywall) {
                AIUpgradePaywall(subscriptions: subscriptions, trigger: .clans, onDismissRequested: { paywall = false })
            }
            .onAppear { rule = clanRule; length = 14; teamTarget = max(10, memberCount * 10) }
        }
    }
    private var picker: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(ChallengeKind.allCases) { k in
                    Button { kind = k; basis = k == .onTargetDays ? "onTarget" : "logging" } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: k.symbol).font(.title2).foregroundStyle(Color.caveOrange).frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(k.title).font(.cave(.headline)).foregroundStyle(Color.primary)
                                Text(k.pitch).font(.cave(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
                    }.hapticButtonStyle(.plain).hapticFeel(.selection).accessibilityIdentifier("challengeKind-\(k.rawValue)")
                }
                Text("One challenge at a time per clan.").font(.cave(.footnote)).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(16)
        }
    }
    @ViewBuilder private func form(_ kind: ChallengeKind) -> some View {
        HapticForm {
            Section { Text(kind.pitch).font(.cave(.callout)) }
            if kind == .streak || kind == .survivor || kind == .teamTotal {
                Section {
                    Picker("Counts", selection: $basis) { Text("Full days logged").tag("logging"); Text("On-target days").tag("onTarget") }
                        .hapticSelection(on: basis)
                    if basis == "onTarget" { RulePicker(rule: $rule) }
                } header: { Text("What counts") } footer: {
                    Text(basis == "logging" ? "A full day is at least 70% of your goal logged, or Done eating." : "A full day in range, against each person’s own goal.").font(.cave(.caption2))
                }
            }
            if kind == .loggingDays {
                Section {
                    Toggle("Any food counts", isOn: $anyFood)
                } footer: { Text(anyFood ? "Logging anything earns the day." : "Only full days count: at least 70% of your goal logged, or Done eating.").font(.cave(.caption2)) }
            }
            if kind == .onTargetDays { Section("Range") { RulePicker(rule: $rule) } }
            if kind == .streak {
                Section {
                    Picker("The day counts when", selection: $streakMode) { Text("Everyone makes it").tag("everyone"); Text("Enough of us make it").tag("percent") }
                        .hapticSelection(on: streakMode)
                    if streakMode == "percent" { Stepper("At least \(streakPercent)%", value: $streakPercent, in: 50...100, step: 10) }
                } header: { Text("Clan streak") }
            }
            if kind == .streak || kind == .survivor {
                Section {
                    Stepper("\(saves) \(kind == .survivor ? (saves == 1 ? "life" : "lives") : (saves == 1 ? "save" : "saves"))", value: $saves, in: 0...5)
                    if saves > 0 {
                        Picker("Every", selection: $savesPeriod) { Text("Week").tag("week"); Text("Month").tag("month"); Text("Whole challenge").tag("challenge") }
                            .hapticSelection(on: savesPeriod)
                    }
                } header: { Text(kind == .survivor ? "Lives" : "Saves") } footer: {
                    Text("A missed day uses one automatically, so one off day doesn’t end it.").font(.cave(.caption2))
                }
            }
            if kind == .survivor {
                Section {
                    Toggle("Last one standing", isOn: $openEnded)
                    if !openEnded { Stepper("\(length) days", value: $length, in: 7...90, step: 7) }
                } footer: { Text(openEnded ? "Runs until one person is left." : "Everyone still in at the end wins.").font(.cave(.caption2)) }
            }
            if kind == .loggingDays || kind == .onTargetDays || kind == .teamTotal {
                Section("Length") { Stepper("\(length) days", value: $length, in: 7...90, step: 7) }
            }
            if kind == .teamTotal { Section("Clan goal") { Stepper("\(teamTarget) days together", value: $teamTarget, in: 10...2000, step: 10) } }
            if kind == .weightLoss {
                Section {
                    Stepper("\(weeks) weeks", value: $weeks, in: 2...12)
                } header: { Text("Length") } footer: {
                    Text("Compares your average weigh-in on days 1–3 with your average on the last 3 days. Credit stops at 1% of body weight a week. For adults only; only the % is shared.").font(.cave(.caption2))
                }
            }
            Section {
                DatePicker("Starts", selection: $start, in: Calendar.current.startOfDay(for: Date())...Date().addingTimeInterval(30 * 86_400), displayedComponents: .date)
            } footer: { Text("Clanmates tap Join before it starts. Nobody new joins once it’s running.").font(.cave(.caption2)) }
            Section {
                Button { create(kind) } label: { Text("Start \(kind.title.lowercased())").frame(maxWidth: .infinity) }
                    .disabled(busy).hapticFeel(.success).accessibilityIdentifier("createChallenge")
            }
            if let message { Section { Text(message).font(.cave(.footnote)).foregroundStyle(.red) } }
        }
    }
    private func create(_ kind: ChallengeKind) {
        busy = true; message = nil
        var settings: [String: Any] = ["basis": basis, "anyFood": anyFood, "streakMode": streakMode, "streakPercent": streakPercent, "teamTarget": teamTarget]
        if basis == "onTarget" || kind == .onTargetDays { settings["rule"] = rule.json }
        var fields: [String: Any] = ["clanId": clanId, "kind": kind.rawValue, "settings": settings, "startsOn": ClanDay.string(start),
                                     "savesCount": saves, "savesPeriod": saves > 0 ? savesPeriod : "challenge"]
        switch kind {
        case .loggingDays, .onTargetDays, .teamTotal: fields["lengthDays"] = length
        case .survivor: if !openEnded { fields["lengthDays"] = length }
        case .weightLoss: fields["weeks"] = weeks
        case .streak: break
        }
        Task {
            do {
                struct Created: Decodable { let challengeId: String }
                let _: Created = try await ClanClient.shared.call("clan/challenge/create", fields)
                UsageStats.shared.event("challenge.started", ["kind": kind.rawValue])
                Haptics.play(.success)
                ClanReporter.shared.sendNow(force: true)
                onCreated()
            } catch let error as ClanError where error.code == "clan_needs_plus" {
                message = "Challenges in a clan of three or more need an admin with Cave Cals+."
                paywall = true
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: Boards

/// The challenge's headline on the clan page.
struct ChallengeCard: View {
    let board: ClanBoard
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: board.kind.symbol).foregroundStyle(Color.caveOrange)
                Text(board.name).font(.cave(.title3)).foregroundStyle(Color.primary)
                Spacer()
                Text(statusText).font(.cave(.footnote)).foregroundStyle(.secondary)
            }
            headline
            if board.canJoin {
                Text("Tap to join").font(.cave(.footnote)).foregroundStyle(Color.caveOrange)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.caveOrange.opacity(0.6), lineWidth: 1.5))
        .contentShape(Rectangle())
    }
    private var statusText: String {
        if board.status == "upcoming" { return "Starts \(ClanDay.label(board.startsOn))" }
        if board.status == "ended" { return "Over" }
        if let total = board.totalDays { return "Day \(min(max(1, board.dayNumber), total)) of \(total)" }
        return "Day \(max(1, board.dayNumber))"
    }
    @ViewBuilder private var headline: some View {
        switch board.kind {
        case .streak:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(board.streak?.length ?? 0)").font(.cave(.largeTitle)).foregroundStyle(Color.caveOrange)
                Text("day streak").font(.cave(.headline))
                Spacer()
                if let record = board.streak?.record, record > 0 { Text("Record \(record)").font(.cave(.footnote)).foregroundStyle(.secondary) }
            }
            Text("\(board.inToday) of \(board.inCount) in today").font(.cave(.callout))
        case .teamTotal:
            if let team = board.team {
                ProgressView(value: Double(min(team.total, team.target)), total: Double(team.target)).tint(.caveOrange)
                Text("\(team.total) of \(team.target) days together").font(.cave(.callout))
            }
        default:
            let leaders = board.entrants.filter { $0.rank == 1 }.map(\.name)
            Text(leaders.isEmpty ? "\(board.entrants.count) in" : "Leading: \(leaders.prefix(2).joined(separator: ", "))\(leaders.count > 2 ? " +\(leaders.count - 2)" : "")")
                .font(.cave(.callout))
        }
    }
}

struct ChallengeBoardView: View {
    let clanId: String
    @State private var board: ClanBoard?
    @State private var isAdmin = false
    @State private var message: String?
    @State private var confirmEnd = false
    @State private var confirmLeave = false
    @State private var eligibility = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let board {
                content(board)
            } else if let message {
                ContentUnavailableView("Couldn’t open the challenge", systemImage: "wifi.slash", description: Text(message))
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .caveScreenBackground()
        .navigationTitle(board?.name ?? "Challenge").navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $eligibility) {
            WeightEligibilitySheet { ok in eligibility = false; if ok { join(confirmed: true) } }
        }
        .confirmationDialog(board?.status == "upcoming" ? "Cancel this challenge?" : "End this challenge now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(board?.status == "upcoming" ? "Cancel challenge" : "End challenge", role: .destructive) { Haptics.play(.warning); end() }.hapticFeel(.none)
            Button("Keep it going", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
        } message: { Text("Results are kept with the clan’s past challenges.") }
        .confirmationDialog("Leave this challenge?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave challenge", role: .destructive) { Haptics.play(.warning); leave() }.hapticFeel(.none)
            Button("Stay in", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
        }
    }
    private func content(_ board: ClanBoard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ChallengeCard(board: board)
            rules(board)
            if board.canJoin {
                Button { join() } label: {
                    Text("Join \(board.name.lowercased())").font(.cave(.headline)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.caveOrange, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }.hapticFeel(.success).accessibilityIdentifier("joinChallenge")
            }
            VStack(spacing: 0) {
                ForEach(board.entrants) { e in row(e, board); if e.id != board.entrants.last?.id { Divider().padding(.leading, 64) } }
            }.background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
            if board.entrants.isEmpty { Text("Nobody has joined yet.").font(.cave(.callout)).foregroundStyle(.secondary) }
            HStack {
                if board.joined && board.status != "ended" {
                    Button("Leave challenge", role: .destructive) { confirmLeave = true }.font(.cave(.callout))
                }
                Spacer()
                if isAdmin && board.status != "ended" {
                    Button(board.status == "upcoming" ? "Cancel challenge" : "End challenge", role: .destructive) { confirmEnd = true }.font(.cave(.callout))
                }
            }
            if let message { Text(message).font(.cave(.footnote)).foregroundStyle(.red) }
        }.padding(16)
    }
    private func rules(_ board: ClanBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ruleLine(board)).font(.cave(.footnote)).foregroundStyle(.secondary)
            if board.savesCount > 0 {
                let unit = board.kind == .survivor ? (board.savesCount == 1 ? "life" : "lives") : (board.savesCount == 1 ? "save" : "saves")
                let period = board.savesPeriod == "week" ? " each week" : board.savesPeriod == "month" ? " each month" : ""
                Text("\(board.savesCount) \(unit)\(period). A missed day uses one.").font(.cave(.footnote)).foregroundStyle(.secondary)
            }
        }
    }
    private func ruleLine(_ board: ClanBoard) -> String {
        let counts = board.settings.basis == "onTarget"
            ? "On-target days count (\((board.settings.rule ?? ClanRule()).summary))."
            : board.settings.anyFood ? "Any day with food logged counts." : "Full days count: 70% of your goal logged, or Done eating."
        switch board.kind {
        case .streak: return counts + (board.settings.streakMode == "everyone" ? " Everyone has to make it." : " At least \(board.settings.streakPercent)% have to make it.")
        case .weightLoss: return "Average of days 1–3 vs. the last 3 days. Credit stops at 1% a week."
        default: return counts
        }
    }
    private func row(_ e: ClanEntrant, _ board: ClanBoard) -> some View {
        HStack(spacing: 12) {
            if [.loggingDays, .onTargetDays, .weightLoss].contains(board.kind) {
                Text(e.rank.map { "\($0)" } ?? "–").font(.cave(.callout)).foregroundStyle(.secondary).frame(width: 18)
            }
            ClanAvatar(photoId: e.photoId, name: e.name, anonymous: e.anonymous, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.cave(.body)).lineLimit(1).foregroundStyle(e.status == "in" ? Color.primary : .secondary)
                if board.kind != .weightLoss { marks(e) }
            }
            Spacer(minLength: 6)
            score(e, board)
        }
        .padding(.horizontal, 12).frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
    private func marks(_ e: ClanEntrant) -> some View {
        HStack(spacing: 4) {
            ForEach(e.recent.keys.sorted(), id: \.self) { day in
                let mark = e.recent[day] ?? nil
                Circle().fill(mark == "made" ? Color.caveOrange : mark == "saved" ? Color.caveOrange.opacity(0.4) : mark == "missed" ? Color.secondary.opacity(0.35) : Color.clear)
                    .overlay(Circle().stroke(Color.secondary.opacity(mark == nil ? 0.3 : 0), lineWidth: 1))
                    .frame(width: 9, height: 9)
            }
            if e.madeToday { CaveIcon(.check, size: 13).foregroundStyle(Color.caveOrange).padding(.leading, 2) }
        }.accessibilityHidden(true)
    }
    @ViewBuilder private func score(_ e: ClanEntrant, _ board: ClanBoard) -> some View {
        switch board.kind {
        case .survivor:
            Text(e.status == "out" ? "Out" : e.status == "left" ? "Left" : "\(e.livesLeft ?? 0) \((e.livesLeft ?? 0) == 1 ? "life" : "lives")")
                .font(.cave(.callout)).foregroundStyle(e.status == "in" ? Color.caveOrange : .secondary)
        case .weightLoss:
            Text(e.creditedLossPct.map { "\($0 >= 0 ? "−" : "+")\(abs($0).formatted(.number.precision(.fractionLength(1))))%" } ?? "No weigh-in")
                .font(.cave(.callout)).foregroundStyle(e.creditedLossPct == nil ? .secondary : Color.caveOrange)
        case .streak:
            Text(e.status == "left" ? "Left" : e.madeToday ? "In today" : "Not yet").font(.cave(.callout)).foregroundStyle(e.madeToday ? Color.caveOrange : .secondary)
        default:
            Text(e.status == "left" ? "Left" : "\(e.points)").font(.cave(.title3)).foregroundStyle(Color.caveOrange)
        }
    }
    private func join(confirmed: Bool = false) {
        guard let board else { return }
        if board.kind == .weightLoss && !confirmed { eligibility = true; return }
        Task {
            do {
                var fields: [String: Any] = ["challengeId": board.id]
                if board.kind == .weightLoss { fields["notClinicianLed"] = true }
                let _: [String: Bool] = try await ClanClient.shared.call("clan/challenge/join", fields)
                Haptics.play(.success); UsageStats.shared.event("challenge.joined", ["kind": board.kind.rawValue])
                await refresh()
                ClanReporter.shared.sendNow(force: true)
            } catch { message = error.localizedDescription }
        }
    }
    private func leave() {
        guard let board else { return }
        Task {
            do { let _: [String: Bool] = try await ClanClient.shared.call("clan/challenge/leave", ["challengeId": board.id]); await refresh() }
            catch { message = error.localizedDescription }
        }
    }
    private func end() {
        guard let board else { return }
        Task {
            do { let _: [String: Bool] = try await ClanClient.shared.call("clan/challenge/end", ["challengeId": board.id]); dismiss() }
            catch { message = error.localizedDescription }
        }
    }
    private func refresh() async {
        do {
            let detail: ClanDetail = try await ClanClient.shared.call("clan/get", ["clanId": clanId])
            isAdmin = detail.isAdmin
            if let updated = detail.challenge { board = updated } else { dismiss() }
        } catch { message = error.localizedDescription }
    }
}

/// Weight challenges are for adults, and not for anyone pregnant, breastfeeding, or in care for an eating
/// disorder. The answer isn't saved or sent; only the birth month and year are, so the server can check age.
struct WeightEligibilitySheet: View {
    var onDone: (Bool) -> Void
    @Environment(WeightStore.self) private var weights
    @State private var clans = ClanStore.shared
    @State private var month = 0
    @State private var year = 0
    @State private var answer: Bool?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            HapticForm {
                if !weights.tracking {
                    Section { Text("Turn on Track weight in About You first, so your weigh-ins can count.").font(.cave(.callout)) }
                }
                if clans.me?.birthMonth == nil || clans.me?.birthYear == nil {
                    Section {
                        Picker("Birth month", selection: $month) {
                            Text("Choose").tag(0)
                            ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                        }.hapticSelection(on: month)
                        Picker("Birth year", selection: $year) {
                            Text("Choose").tag(0)
                            ForEach((1920...(Calendar.current.component(.year, from: Date()) - 13)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                        }.hapticSelection(on: year)
                    } header: { Text("Birthday") } footer: { Text("Weight challenges are for adults 18 and older. Never shown to anyone.").font(.cave(.caption2)) }
                }
                Section {
                    Picker("Are you pregnant, breastfeeding, or getting care for an eating disorder?", selection: $answer) {
                        Text("Choose").tag(Bool?.none); Text("No").tag(Bool?.some(false)); Text("Yes").tag(Bool?.some(true))
                    }.pickerStyle(.inline).labelsHidden().hapticSelection(on: answer)
                } header: { Text("Are you pregnant, breastfeeding, or getting care for an eating disorder?").textCase(nil) } footer: {
                    Text(answer == true ? "Weight challenges aren’t a fit right now. Logging and streak challenges are still open to you." : "Your answer stays on this iPhone.").font(.cave(.caption2))
                }
                Section {
                    Button { confirm() } label: { Text("Join").frame(maxWidth: .infinity) }
                        .disabled(answer != false || !weights.tracking || ((clans.me?.birthMonth == nil || clans.me?.birthYear == nil) && (month == 0 || year == 0)))
                        .accessibilityIdentifier("weightEligibilityJoin")
                }
                if let message { Section { Text(message).font(.cave(.footnote)).foregroundStyle(.red) } }
            }
            .caveScreenBackground()
            .navigationTitle("Weight challenge").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(false) }.hapticButtonStyle(.automatic) } }
        }
    }
    private func confirm() {
        guard answer == false else { return }
        Task {
            if month > 0 && year > 0 {
                do {
                    let profile: ClanProfile = try await ClanClient.shared.call("clan/me/update", ["birthMonth": month, "birthYear": year])
                    clans.setProfile(profile)
                } catch { message = error.localizedDescription; return }
            }
            onDone(true)
        }
    }
}

// MARK: Home

/// The one line between Home's header and the calorie card, only while you're in a running challenge.
struct HomeClanStrip: View {
    let clan: ClanListItem
    let challenge: ClanChallengeSummary
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image("CaveCampfire").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                    .foregroundStyle(Color.caveOrange).accessibilityHidden(true)
                (Text(clan.name).bold() + Text(" · " + ClanStatusText.line(challenge)))
                    .font(.cave(.footnote)).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                CaveIcon(.chevronRight, size: 12).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.caveOrange.opacity(0.7), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain)
        .accessibilityLabel("\(clan.name), \(ClanStatusText.line(challenge))")
        .accessibilityHint("Opens the clan")
        .accessibilityIdentifier("clanStatus")
    }
}

/// Home's clan upkeep, kept out of Home's long modifier chain: refresh on open and return, send reports when
/// leaving, and open invites and clan notifications.
struct ClanHomeHooks: ViewModifier {
    let phase: ScenePhase
    let pending: ClanRouter.Request?
    let open: () -> Void
    func body(content: Content) -> some View {
        content
            .task { await ClanStore.shared.refresh(); open() }
            .onChange(of: pending) { _, request in if request != nil { open() } }
            .onChange(of: phase) { _, value in
                if value == .active { Task { await ClanStore.shared.refresh() } }
                if value == .active || value == .background { ClanReporter.shared.sendNow() }
            }
    }
}
