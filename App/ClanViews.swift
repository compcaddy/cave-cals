import SwiftUI

/// The campfire: sign in, then your clans, joining by code, and starting one.
struct ClansScreen: View {
    @State private var clans = ClanStore.shared
    @Environment(\.dismiss) private var dismiss
    /// From an invite link: opens the Join page for that code.
    var joinCode: String?
    var openClanId: String?
    @State private var path: [ClanRoute] = []
    @State private var joining: JoinSheet?
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !clans.signedIn {
                    ClanSignInView()
                } else if clans.me?.needsName == true {
                    ClanProfileView(firstTime: true)
                } else {
                    list
                }
            }
            .caveScreenBackground()
            .navigationTitle(clans.signedIn && clans.me?.needsName != true ? "Clans" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic).accessibilityIdentifier("clansDone") }
                if clans.signedIn && clans.me?.needsName != true {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: ClanRoute.profile) { CaveIcon(.person, size: 22) }
                            .accessibilityLabel("Clan profile").accessibilityIdentifier("clanProfile")
                    }
                }
            }
            .navigationDestination(for: ClanRoute.self) { route in
                switch route {
                case .clan(let id): ClanDetailView(clanId: id).hapticOnPush()
                case .challenge(let clanId): ChallengeBoardView(clanId: clanId).hapticOnPush()
                case .profile: ClanProfileView().hapticOnPush()
                }
            }
        }
        .sheet(item: $joining) { sheet in
            JoinClanSheet(code: sheet.code) { clanId in joining = nil; path = [.clan(clanId)] }
        }
        .sheet(isPresented: $creating) {
            CreateClanSheet { clanId in creating = false; path = [.clan(clanId)] }
        }
        .task { await clans.refresh() }
        .onAppear {
            if let joinCode { joining = JoinSheet(code: joinCode) }
            if let openClanId { path = [.clan(openClanId)] }
        }
        .onChange(of: clans.signedIn) { _, signedIn in
            // An invite link opened before signing in carries on once signed in.
            if signedIn, let joinCode, joining == nil { joining = JoinSheet(code: joinCode) }
        }
    }
    struct JoinSheet: Identifiable { var code: String?; var id: String { code ?? "typed" } }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if clans.clans.isEmpty && clans.loaded {
                    VStack(spacing: 10) {
                        Image("CaveCampfire").renderingMode(.template).resizable().scaledToFit().frame(width: 70, height: 70)
                            .foregroundStyle(Color.caveOrange).accessibilityHidden(true)
                        Text("No clan yet").font(.cave(.title2))
                        Text("Start one and invite friends, or join with a code someone sent you.")
                            .font(.cave(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                ForEach(clans.clans) { clan in
                    NavigationLink(value: ClanRoute.clan(clan.id)) { ClanCard(clan: clan) }
                        .buttonStyle(.plain).accessibilityIdentifier("clanCard")
                }
                HStack(spacing: 12) {
                    Button { creating = true } label: { actionLabel("Start a clan", "plus") }.accessibilityIdentifier("startClan")
                    Button { joining = JoinSheet(code: nil) } label: { actionLabel("Join with code", "number") }.accessibilityIdentifier("joinWithCode")
                }.padding(.top, 6)
                if let error = clans.error { Text(error).font(.cave(.footnote)).foregroundStyle(.red) }
            }.padding(16)
        }
        .refreshable { await clans.refresh() }
    }
    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 8) { Image(systemName: symbol); Text(title) }
            .font(.cave(.headline)).frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.caveOrange.opacity(0.5), lineWidth: 1.5))
            .foregroundStyle(Color.caveOrange)
    }
}

enum ClanRoute: Hashable { case clan(String), challenge(String), profile }

struct ClanCard: View {
    let clan: ClanListItem
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clan.name).font(.cave(.title3)).foregroundStyle(Color.primary).lineLimit(1)
                Text("\(clan.memberCount) \(clan.memberCount == 1 ? "member" : "members")").font(.cave(.footnote)).foregroundStyle(.secondary)
                if let c = clan.challenge {
                    HStack(spacing: 6) {
                        Image(systemName: c.kind.symbol).foregroundStyle(Color.caveOrange)
                        Text(c.status == "upcoming" ? "\(c.name) starts \(ClanDay.label(c.startsOn))" : "\(c.name) · \(ClanStatusText.line(c))")
                            .font(.cave(.footnote)).foregroundStyle(Color.primary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if clan.unread > 0 { ClanBadge(count: clan.unread) }
            CaveIcon(.chevronRight, size: 14).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

/// The red count on the campfire and on clan cards.
struct ClanBadge: View {
    let count: Int
    var body: some View {
        Text(count > 9 ? "9+" : "\(count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(Color.red, in: Capsule())
            .accessibilityLabel("\(count) new")
    }
}

// MARK: Join and create

struct JoinClanSheet: View {
    var code: String?
    var onJoined: (String) -> Void
    @State private var typed = ""
    @State private var preview: ClanPreview?
    @State private var anonymous = false
    @State private var busy = false
    @State private var message: String?
    @State private var paywall = false
    @State private var subscriptions = AISubscriptions()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            HapticForm {
                if let preview {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preview.name).font(.cave(.title2))
                            Text("\(preview.memberCount) \(preview.memberCount == 1 ? "member" : "members")").font(.cave(.footnote)).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                    if preview.alreadyMember {
                        Section { Button("Open clan") { onJoined(preview.clanId) } }
                    } else if preview.full {
                        Section { Text("This clan is full.").foregroundStyle(.secondary) }
                    } else {
                        Section {
                            Toggle("Join as a Cave person", isOn: $anonymous).accessibilityIdentifier("joinAnonymous")
                        } footer: {
                            Text("Cave people show as “Cave person” with no photo. Your days still count. You can change this anytime.").font(.cave(.caption2))
                        }
                        Section {
                            Button { join(preview) } label: { Text("Join \(preview.name)").frame(maxWidth: .infinity) }
                                .disabled(busy).hapticFeel(.success).accessibilityIdentifier("joinClan")
                        }
                    }
                } else {
                    Section {
                        TextField("6-letter code", text: $typed).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.system(size: 26, weight: .semibold, design: .monospaced)).focused($focused)
                            .onSubmit { look(typed) }.accessibilityIdentifier("joinCode")
                            .keyboardInputArea()
                    } footer: { Text("The code is in the invite link, after cavecals.com/join/.").font(.cave(.caption2)) }
                    Section {
                        Button { look(typed) } label: { Text("Find clan").frame(maxWidth: .infinity) }
                            .disabled(ClanLinks.normalize(typed).count != 6 || busy).accessibilityIdentifier("findClan")
                    }
                }
                if busy { Section { ProgressView().frame(maxWidth: .infinity) } }
                if let message { Section { Text(message).foregroundStyle(.red).font(.cave(.footnote)) } }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle("Join a clan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) } }
            .navigationDestination(isPresented: $paywall) {
                AIUpgradePaywall(subscriptions: subscriptions, trigger: .clans, onDismissRequested: { paywall = false })
            }
            .task {
                if let code { typed = code; look(code) } else { focused = true }
            }
        }
    }
    private func look(_ text: String) {
        let code = ClanLinks.normalize(text)
        guard code.count == 6 else { return }
        busy = true; message = nil
        Task {
            do { preview = try await ClanClient.shared.call("clan/preview", ["code": code]) }
            catch { message = error.localizedDescription; ClanStore.shared.handle(error) }
            busy = false
        }
    }
    private func join(_ preview: ClanPreview) {
        busy = true; message = nil
        Task {
            do {
                struct Joined: Decodable { let clanId: String }
                let joined: Joined = try await ClanClient.shared.call("clan/join", ["code": ClanLinks.normalize(typed), "anonymous": anonymous])
                Haptics.play(.success)
                UsageStats.shared.event("clan.joined", ["anonymous": anonymous ? "yes" : "no"])
                await ClanStore.shared.refresh()
                await ClanStore.shared.requestPushPermission()
                ClanReporter.shared.sendNow(force: true)
                onJoined(joined.clanId)
            } catch let error as ClanError where error.code == "clan_needs_plus" {
                message = "This clan needs its admin to have Cave Cals+ to add more people. Ask them, or get Cave Cals+ and start your own."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

struct CreateClanSheet: View {
    var onCreated: (String) -> Void
    @State private var name = ""
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            HapticForm {
                Section {
                    TextField("The Cavemen", text: $name).focused($focused).submitLabel(.done).onSubmit(create)
                        .accessibilityIdentifier("newClanName").keyboardInputArea()
                } header: { Text("Clan name") } footer: {
                    Text("A clan of two is free. Adding a third person needs Cave Cals+.").font(.cave(.caption2))
                }
                Section {
                    Button(action: create) { Text("Start clan").frame(maxWidth: .infinity) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || busy).hapticFeel(.success)
                        .accessibilityIdentifier("createClan")
                }
                if let message { Section { Text(message).foregroundStyle(.red).font(.cave(.footnote)) } }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle("Start a clan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) } }
            .onAppear { focused = true }
        }
    }
    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !busy else { return }
        busy = true; message = nil
        Task {
            do {
                struct Created: Decodable { let clanId: String }
                let created: Created = try await ClanClient.shared.call("clan/create", ["name": trimmed])
                Haptics.play(.success)
                UsageStats.shared.event("clan.created")
                await ClanStore.shared.refresh()
                await ClanStore.shared.requestPushPermission()
                ClanReporter.shared.sendNow(force: true)
                onCreated(created.clanId)
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: Clan page

struct ClanDetailView: View {
    let clanId: String
    @State private var detail: ClanDetail?
    @State private var message: String?
    @State private var member: ClanMember?
    @State private var newChallenge = false
    @State private var settings = false
    @State private var weekStart: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 18) {
                    header(detail)
                    if let board = detail.challenge {
                        NavigationLink(value: ClanRoute.challenge(clanId)) { ChallengeCard(board: board) }
                            .buttonStyle(.plain).accessibilityIdentifier("challengeCard")
                    } else if detail.isAdmin {
                        Button { newChallenge = true } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "flag.checkered").font(.title2)
                                Text("Start a challenge").font(.cave(.headline))
                                Text("A streak, Survivor, logging days, and more.").font(.cave(.footnote)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(18)
                            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.caveOrange.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                            .foregroundStyle(Color.caveOrange)
                        }.accessibilityIdentifier("startChallenge")
                    }
                    if let accountability = detail.accountability {
                        AccountabilityGrid(accountability: accountability, members: detail.members, today: detail.me.today,
                                           onWeek: { weekStart = $0; load() })
                    }
                    membersSection(detail)
                    if !detail.history.isEmpty { historySection(detail) }
                    if let message { Text(message).font(.cave(.footnote)).foregroundStyle(.red) }
                }.padding(16)
            } else if let message {
                ContentUnavailableView("Couldn’t open the clan", systemImage: "wifi.slash", description: Text(message))
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .refreshable { await reload() }
        .navigationTitle(detail?.clan.name ?? "Clan").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { CaveIcon(.gear, size: 22) }
                    .hapticButtonStyle(.automatic).accessibilityLabel("Clan settings").accessibilityIdentifier("clanSettings")
                    .disabled(detail == nil)
            }
        }
        .sheet(item: $member) { m in
            if let detail { MemberSheet(clanId: clanId, member: m, viewerIsAdmin: detail.isAdmin, viewerRole: detail.me.role, onChange: load) }
        }
        .sheet(isPresented: $newChallenge) {
            if let detail { NewChallengeView(clanId: clanId, clanRule: detail.clan.rule, memberCount: detail.members.count, onCreated: { newChallenge = false; load() }) }
        }
        .sheet(isPresented: $settings) {
            if let detail { ClanSettingsView(detail: detail, onChange: load, onLeft: { settings = false; dismiss() }) }
        }
        .task { await reload() }
        // Coming back from the challenge board shows its latest state.
        .onAppear { if detail != nil { load() } }
    }
    private func load() { Task { await reload() } }
    private func reload() async {
        do {
            var fields: [String: Any] = ["clanId": clanId]
            if let weekStart { fields["weekStart"] = weekStart }
            detail = try await ClanClient.shared.call("clan/get", fields); message = nil
            await ClanStore.shared.refresh()
        } catch { message = error.localizedDescription; ClanStore.shared.handle(error) }
    }
    private func header(_ detail: ClanDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(detail.members.count) \(detail.members.count == 1 ? "member" : "members")").font(.cave(.callout)).foregroundStyle(.secondary)
                if detail.clan.bestStreak > 0 {
                    Text("· Record streak \(detail.clan.bestStreak) days").font(.cave(.callout)).foregroundStyle(.secondary)
                }
            }
            ShareLink(item: ClanLinks.inviteURL(detail.clan.inviteCode),
                      subject: Text("Join my clan on Cave Cals"),
                      message: Text("Join \(detail.clan.name) on Cave Cals! Tap the link, or open the campfire in Cave Cals and enter code \(detail.clan.inviteCode).")) {
                HStack(spacing: 8) { Image(systemName: "person.badge.plus"); Text("Invite to clan") }
                    .font(.cave(.headline)).frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.caveOrange, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.play(.tap); UsageStats.shared.event("clan.invite") })
            .accessibilityIdentifier("inviteToClan")
            Text("Code \(detail.clan.inviteCode)").font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).textSelection(.enabled)
        }
    }
    private func membersSection(_ detail: ClanDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Members").font(.cave(.title3))
            VStack(spacing: 0) {
                ForEach(detail.members) { m in
                    Button { member = m } label: {
                        HStack(spacing: 12) {
                            ClanAvatar(photoId: m.photoId, name: m.name, anonymous: m.anonymous, size: 40)
                            Text(m.name).font(.cave(.body)).foregroundStyle(Color.primary).lineLimit(1)
                            if m.role == "owner" || m.role == "admin" {
                                Text(m.role == "owner" ? "Owner" : "Admin").font(.cave(.caption)).foregroundStyle(Color.caveOrange)
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(Color.caveOrange.opacity(0.12), in: Capsule())
                            }
                            Spacer()
                            CaveIcon(.chevronRight, size: 12).foregroundStyle(.secondary)
                        }.padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("member-\(m.name)")
                    if m.id != detail.members.last?.id { Divider().padding(.leading, 66) }
                }
            }.background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func historySection(_ detail: ClanDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past challenges").font(.cave(.title3))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(detail.history) { h in
                    HStack(spacing: 12) {
                        Image(systemName: h.kind.symbol).foregroundStyle(Color.caveOrange).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(.cave(.body))
                            Text(historyLine(h)).font(.cave(.footnote)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.horizontal, 14).frame(minHeight: 56)
                    if h.id != detail.history.last?.id { Divider().padding(.leading, 52) }
                }
            }.background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func historyLine(_ h: ClanHistoryItem) -> String {
        if h.kind == .streak, let length = h.result?.streak?.length { return "\(length) \(length == 1 ? "day" : "days")\(h.result?.record == true ? " · Record!" : "")" }
        if h.kind == .teamTotal, let team = h.result?.team { return team.reached ? "Goal reached: \(team.target) days" : "\(team.total) of \(team.target) days" }
        let names = h.result?.winnerNames ?? []
        if names.isEmpty { return "Ended \(ClanDay.label(h.endsOn ?? h.startsOn))" }
        return names.count == 1 ? "\(names[0]) won" : names.count == 2 ? "\(names[0]) and \(names[1]) won" : "\(names.count) cavemen tied"
    }
}

// MARK: Accountability

/// Members down the side, the week across: ✓ full day, a dot for some food, – nothing; ± shows % of goal.
struct AccountabilityGrid: View {
    let accountability: ClanAccountability
    let members: [ClanMember]
    let today: String
    var onWeek: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accountability").font(.cave(.title3))
                Spacer()
                Button { onWeek(ClanDay.adding(-7, to: accountability.days[0])) } label: { CaveIcon(.chevronLeft, size: 16).frame(width: 44, height: 36) }
                    .hapticFeel(.selection).accessibilityLabel("Previous week")
                Button { onWeek(ClanDay.adding(7, to: accountability.days[0])) } label: { CaveIcon(.chevronRight, size: 16).frame(width: 44, height: 36) }
                    .hapticFeel(.selection).accessibilityLabel("Next week")
                    .disabled(accountability.days.last ?? today >= today)
            }
            Text(accountability.mode == "percent" ? "Calories vs. each person’s own goal. Range: \(accountability.rule.shortTitle.lowercased())." : "Did each person log a full day?")
                .font(.cave(.footnote)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer().frame(width: 96)
                    ForEach(accountability.days, id: \.self) { day in
                        Text(ClanDay.weekdayLetter(day)).font(.cave(.caption2)).foregroundStyle(day == today ? Color.caveOrange : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 6)
                ForEach(members) { m in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            ClanAvatar(photoId: m.photoId, name: m.name, anonymous: m.anonymous, size: 24)
                            Text(m.name).font(.cave(.caption)).lineLimit(1)
                        }.frame(width: 96, alignment: .leading)
                        ForEach(accountability.days, id: \.self) { day in
                            cell(accountability.cells[m.personId]?[day] ?? nil, future: day > today).frame(maxWidth: .infinity, minHeight: 34)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowLabel(m))
                    if let w = accountability.weekly[m.personId], w.logged > 0 {
                        Text(weeklyLine(w)).font(.cave(.caption2)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 96).padding(.bottom, 4)
                    }
                }
            }.padding(12).background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityIdentifier("accountabilityGrid")
    }
    @ViewBuilder private func cell(_ cell: ClanCell?, future: Bool) -> some View {
        if future || cell == nil { Text(" ") }
        else if let cell, let percent = cell.percent {
            let delta = percent - 100
            Text(delta == 0 ? "0%" : "\(delta > 0 ? "+" : "−")\(abs(delta))%").font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(cell.inRange == true ? Color.caveOrange : .secondary).minimumScaleFactor(0.6).lineLimit(1)
        } else if let cell {
            switch cell.state {
            case "full": CaveIcon(.check, size: 18).foregroundStyle(Color.caveOrange)
            case "partial": Circle().fill(Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
            case "today": cell.logged ? AnyView(Circle().stroke(Color.caveOrange, lineWidth: 2).frame(width: 12, height: 12)) : AnyView(Text("·").foregroundStyle(.secondary))
            default: Text("–").foregroundStyle(.secondary)
            }
        }
    }
    private func weeklyLine(_ w: ClanAccountability.Weekly) -> String {
        var line = "\(w.full) of 7 full"
        if let avg = w.averagePercent { line += " · avg \(avg - 100 >= 0 ? "+" : "−")\(abs(avg - 100))%" }
        return line
    }
    private func rowLabel(_ m: ClanMember) -> String {
        let cells = accountability.days.compactMap { day -> String? in
            guard let cell = accountability.cells[m.personId]?[day] ?? nil else { return nil }
            let state = cell.percent.map { "\($0)% of goal" } ?? (cell.state == "full" ? "full day" : cell.state == "partial" ? "some food" : cell.state == "today" ? (cell.logged ? "logging today" : "nothing yet today") : "no log")
            return "\(ClanDay.label(day)): \(state)"
        }
        return "\(m.name). " + cells.joined(separator: ", ")
    }
}

// MARK: Members

struct MemberSheet: View {
    let clanId: String
    let member: ClanMember
    let viewerIsAdmin: Bool
    let viewerRole: String
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var confirmRemove = false
    @State private var reporting = false

    var body: some View {
        NavigationStack {
            HapticForm {
                Section {
                    HStack(spacing: 14) {
                        ClanAvatar(photoId: member.photoId, name: member.name, anonymous: member.anonymous, size: 56)
                        VStack(alignment: .leading) {
                            Text(member.name).font(.cave(.title3))
                            Text(member.role == "owner" ? "Owner" : member.role == "admin" ? "Admin" : "Member").font(.cave(.footnote)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                if !member.isMe {
                    Section("Send") {
                        ForEach(Array(["Fire need food! Log today.", "Cave waiting on you.", "No log yet. Ugh!"].enumerated()), id: \.offset) { index, text in
                            Button { send("nudge", index) } label: { Label(text, systemImage: "hand.point.right") }
                        }
                        ForEach(Array(["Strong caveman!", "Fire burn bright!", "Me proud of you!"].enumerated()), id: \.offset) { index, text in
                            Button { send("cheer", index) } label: { Label(text, systemImage: "hands.clap") }
                        }
                    }.disabled(member.blocked)
                    if viewerIsAdmin && member.role != "owner" {
                        Section("Admin") {
                            if member.role == "member" { Button("Make admin") { role("admin") } }
                            else if viewerRole == "owner" { Button("Remove admin") { role("member") } }
                            Button("Remove from clan", role: .destructive) { confirmRemove = true }
                        }
                    }
                    Section {
                        if !member.anonymous { Button("Report name or photo") { reporting = true } }
                        Button(member.blocked ? "Unblock" : "Block", role: member.blocked ? nil : .destructive) { block(!member.blocked) }
                    } footer: {
                        Text("Blocking hides their name and photo from you and stops their nudges. They aren’t told.").font(.cave(.caption2))
                    }
                }
                if let message { Section { Text(message).font(.cave(.footnote)).foregroundStyle(message.hasPrefix("Sent") ? Color.secondary : .red) } }
            }
            .caveScreenBackground()
            .navigationTitle(member.isMe ? "You" : member.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) } }
            .confirmationDialog("Remove \(member.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Haptics.play(.warning); remove() }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: { Text("They leave the clan and any running challenge from today.") }
            .confirmationDialog("What’s wrong?", isPresented: $reporting, titleVisibility: .visible) {
                Button("Their name") { Haptics.play(.tap); report("name") }.hapticFeel(.none)
                if member.photoId != nil { Button("Their photo") { Haptics.play(.tap); report("photo") }.hapticFeel(.none) }
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: { Text("Cave Cals reviews reports within a day and removes anything hateful, sexual, or bullying.") }
        }
        .presentationDetents([.medium, .large])
    }
    private func run(_ path: String, _ fields: [String: Any], done: String? = nil, close: Bool = false) {
        Task {
            do {
                let _: [String: Bool] = try await ClanClient.shared.call(path, fields)
                if let done { message = done }
                onChange()
                if close { dismiss() }
            } catch { message = error.localizedDescription }
        }
    }
    private func send(_ kind: String, _ index: Int) {
        Haptics.play(.success)
        UsageStats.shared.event("clan.nudge", ["kind": kind])
        run("clan/nudge", ["clanId": clanId, "personId": member.personId, "kind": kind, "message": index], done: "Sent!")
    }
    private func role(_ role: String) { run("clan/member/role", ["clanId": clanId, "personId": member.personId, "role": role], close: true) }
    private func remove() { run("clan/member/remove", ["clanId": clanId, "personId": member.personId], close: true) }
    private func block(_ blocked: Bool) { run("clan/block", ["personId": member.personId, "blocked": blocked], close: true) }
    private func report(_ kind: String) {
        UsageStats.shared.event("clan.report", ["kind": kind])
        run("clan/report", ["kind": kind, "personId": member.personId, "clanId": clanId], done: "Sent. Thanks for keeping the cave friendly.")
    }
}

// MARK: Settings

struct ClanSettingsView: View {
    let detail: ClanDetail
    var onChange: () -> Void
    var onLeft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountability = "off"
    @State private var rule = ClanRule()
    @State private var ruleChoice = "clan"
    @State private var anonymous = false
    @State private var muted = false
    @State private var myRule = ClanRule()
    @State private var message: String?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            HapticForm {
                Section {
                    Toggle("Be a Cave person here", isOn: $anonymous).accessibilityIdentifier("clanAnonymous")
                    Toggle("Mute this clan", isOn: $muted)
                } header: { Text("You") } footer: {
                    Text("A Cave person shows with no name or photo, even to admins. Muting stops this clan’s notifications.").font(.cave(.caption2))
                }
                if detail.clan.ruleChoice == "member" {
                    Section("Your range") { RulePicker(rule: $myRule) }
                }
                if detail.isAdmin {
                    Section("Clan name") {
                        TextField("Clan name", text: $name).submitLabel(.done).onSubmit { save(["name": name]) }.keyboardInputArea()
                    }
                    Section {
                        Picker("Show", selection: $accountability) {
                            Text("Off").tag("off"); Text("Yes / no").tag("logged"); Text("± goal").tag("percent")
                        }.pickerStyle(.segmented).hapticSelection(on: accountability).accessibilityIdentifier("accountabilityMode")
                    } header: { Text("Accountability") } footer: {
                        Text(accountability == "off" ? "Members don’t see each other’s days."
                             : accountability == "logged" ? "Everyone sees whether each person logged a full day. Never calories or food."
                             : "Everyone sees how close each person’s day was to their own goal, as a %. Never calories or food.")
                            .font(.cave(.caption2))
                    }
                    Section {
                        Picker("Range", selection: $ruleChoice) { Text("One for everyone").tag("clan"); Text("Each picks their own").tag("member") }
                            .hapticSelection(on: ruleChoice)
                        if ruleChoice == "clan" { RulePicker(rule: $rule) }
                    } header: { Text("On-target range") } footer: {
                        Text("Always measured against each person’s own calorie goal.").font(.cave(.caption2))
                    }
                    Section {
                        Button("New invite code") { resetCode() }
                    } footer: { Text("The old link and code stop working.").font(.cave(.caption2)) }
                }
                Section {
                    Button("Report clan name") { report() }
                    Button("Leave clan", role: .destructive) { confirmLeave = true }.accessibilityIdentifier("leaveClan")
                    if detail.me.role == "owner" { Button("Delete clan", role: .destructive) { confirmDelete = true } }
                }
                if let message { Section { Text(message).font(.cave(.footnote)).foregroundStyle(.red) } }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle("Clan settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { commitName(); dismiss() }.hapticButtonStyle(.automatic) } }
            .onAppear {
                name = detail.clan.name; accountability = detail.clan.accountability; rule = detail.clan.rule; ruleChoice = detail.clan.ruleChoice
                anonymous = detail.me.anonymous; muted = detail.me.muted; myRule = detail.me.rule ?? detail.clan.rule
                DispatchQueue.main.async { loaded = true }
            }
            .onChange(of: anonymous) { if loaded { member(["anonymous": anonymous]) } }
            .onChange(of: muted) { if loaded { member(["muted": muted]) } }
            .onChange(of: myRule) { if loaded { member(["rule": myRule.json]) } }
            .onChange(of: accountability) { if loaded { save(["accountability": accountability]) } }
            .onChange(of: rule) { if loaded { save(["rule": rule.json]) } }
            .onChange(of: ruleChoice) { if loaded { save(["ruleChoice": ruleChoice]) } }
            .confirmationDialog("Leave \(detail.clan.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave clan", role: .destructive) { Haptics.play(.warning); leave() }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: { Text("You’ll stop counting in any running challenge from today.") }
            .confirmationDialog("Delete \(detail.clan.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete clan", role: .destructive) { Haptics.play(.warning); deleteClan() }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: { Text("Everyone leaves, and its history is gone. This can’t be undone.") }
        }
    }
    private func call(_ path: String, _ fields: [String: Any], then: (() -> Void)? = nil) {
        Task {
            do {
                let _: [String: Bool] = try await ClanClient.shared.call(path, fields)
                message = nil; onChange(); then?()
            } catch { message = error.localizedDescription }
        }
    }
    private func save(_ fields: [String: Any]) { call("clan/update", fields.merging(["clanId": detail.clan.id]) { a, _ in a }) }
    private func member(_ fields: [String: Any]) { call("clan/member/settings", fields.merging(["clanId": detail.clan.id]) { a, _ in a }) }
    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isAdmin, trimmed != detail.clan.name, trimmed.count >= 2 { save(["name": trimmed]) }
    }
    private func resetCode() {
        Task {
            struct Code: Decodable { let inviteCode: String }
            do { let _: Code = try await ClanClient.shared.call("clan/code/reset", ["clanId": detail.clan.id]); Haptics.play(.success); onChange() }
            catch { message = error.localizedDescription }
        }
    }
    private func report() { call("clan/report", ["kind": "clanName", "clanId": detail.clan.id]) { message = nil } }
    private func leave() {
        call("clan/leave", ["clanId": detail.clan.id]) {
            UsageStats.shared.event("clan.left")
            Task { await ClanStore.shared.refresh() }
            onLeft()
        }
    }
    private func deleteClan() {
        call("clan/delete", ["clanId": detail.clan.id]) { Task { await ClanStore.shared.refresh() }; onLeft() }
    }
}

/// At or under / within X% / up to X% over, with the percent when it applies.
struct RulePicker: View {
    @Binding var rule: ClanRule
    var body: some View {
        Picker("On target", selection: $rule.kind) {
            Text("At or under goal").tag(ClanRule.Kind.atOrUnder)
            Text("Within a %").tag(ClanRule.Kind.withinPercent)
            Text("Up to a % over").tag(ClanRule.Kind.upToPercentOver)
        }.hapticSelection(on: rule.kind)
        if rule.kind != .atOrUnder {
            Stepper("\(rule.percent)%", value: $rule.percent, in: ClanRule.percents)
        }
    }
}

// MARK: Settings → Clans

/// Which clan alerts arrive as notifications (saved on your clan profile), and your clan account.
struct ClanNotificationSettingsSection: View {
    @State private var clans = ClanStore.shared
    @State private var prefs: [String: Bool] = [:]
    private let switches: [(key: String, title: String)] = [
        ("evening", "Fire going out (7 PM)"), ("nudges", "Nudges and cheers"), ("updates", "Challenge updates"),
        ("milestones", "Streak milestones"), ("members", "New members (admins)"),
    ]
    var body: some View {
        if clans.signedIn {
            Section {
                ForEach(switches, id: \.key) { item in
                    Toggle(item.title, isOn: Binding(get: { prefs[item.key] ?? true }, set: { save(item.key, $0) }))
                }
                NavigationLink("Clan profile") { ClanProfileView().hapticOnPush() }
            } header: { Text("Clans") } footer: {
                Text("Mute a single clan from its settings. Your food stays private; clanmates see only whether your day counted.").font(.cave(.caption2))
            }
            .onAppear { prefs = clans.me?.alertPrefs ?? [:] }
        }
    }
    private func save(_ key: String, _ on: Bool) {
        prefs[key] = on
        Task {
            if let profile: ClanProfile = try? await ClanClient.shared.call("clan/me/update", ["alertPrefs": [key: on]]) { clans.setProfile(profile) }
        }
    }
}
