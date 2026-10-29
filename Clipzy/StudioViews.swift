import SwiftUI
import AVKit

// MARK: - Screen B: Unified studio workspace

struct UnifiedStudioScreen: View {
    @Bindable var vm: ClipzViewModel
    let isKeyboardOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Hidden while the keyboard is up, as on Android.
            if !isKeyboardOpen {
                StudioVideoStage(vm: vm)
            }

            HStack(spacing: 8) {
                WorkspaceTabButton(title: "AI Director", badge: nil, selected: vm.studioTab == "director") { vm.studioTab = "director" }
                WorkspaceTabButton(title: "Subtitles", badge: vm.words.isEmpty ? nil : "\(vm.words.count)",
                                   selected: vm.studioTab == "transcript") { vm.studioTab = "transcript" }
                WorkspaceTabButton(title: "Timeline", badge: "v\(vm.timelineVersion)",
                                   selected: vm.studioTab == "timeline") { vm.studioTab = "timeline" }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.surface1)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            Group {
                switch vm.studioTab {
                case "transcript": StudioTranscriptSection(vm: vm)
                case "timeline": StudioTimelineSection(vm: vm)
                default: StudioDirectorSection(vm: vm, isKeyboardOpen: isKeyboardOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
    }
}

struct WorkspaceTabButton: View {
    let title: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.clipz(12, selected ? .bold : .medium)).foregroundStyle(selected ? Theme.textWhite : Theme.textMuted)
                if let badge {
                    Text(badge).font(.clipz(9.5, .heavy)).foregroundStyle(selected ? .black : Theme.textMuted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(selected ? Theme.coral : Theme.surface2, in: Capsule())
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.surface3 : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.coral.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Video stage

@MainActor
final class LoopingPlayer {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var resumeOnAppear = false

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }

    /// Stage is hidden (keyboard up / leaving studio): pause, but remember if it was playing.
    func suspend() {
        resumeOnAppear = player.timeControlStatus != .paused
        player.pause()
    }

    /// Stage is shown again: resume only if it was playing when hidden, so a user pause sticks.
    func resume() {
        if resumeOnAppear { player.play() }
        resumeOnAppear = false
    }
}

struct LoopingVideoView: View {
    let holder: LoopingPlayer

    var body: some View {
        VideoPlayer(player: holder.player)
            .onAppear { holder.resume() }
            .onDisappear { holder.suspend() }
    }
}

struct StudioVideoStage: View {
    @Bindable var vm: ClipzViewModel

    private var activeFile: URL? { vm.videoSourceMode == "render" ? vm.localRenderFile : vm.localOriginalFile }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StageChip(label: vm.renders.isEmpty ? "Results" : "Rendered (\(vm.renders[0].profile))",
                          selected: vm.videoSourceMode == "render") { vm.videoSourceMode = "render" }
                StageChip(label: "Original", selected: vm.videoSourceMode == "original") {
                    vm.videoSourceMode = "original"
                    vm.loadOriginalVideo()
                }
                Spacer()

                if let f = activeFile, FileManager.default.fileExists(atPath: f.path) {
                    Button { vm.saveCurrentVideoToPhotos() } label: {
                        HStack(spacing: 4) {
                            VectorIcon(kind: .download, size: 12, color: Theme.coral)
                            Text("Save MP4").font(.clipz(11, .bold)).foregroundStyle(Theme.coral)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.coral.opacity(0.4)))
                    }.buttonStyle(.plain)
                }

                Button { vm.videoExpanded.toggle() } label: {
                    Text(vm.videoExpanded ? "Hide ▲" : "Video ▼").font(.clipz(11, .medium)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)

            if vm.videoExpanded {
                ZStack {
                    Color.black
                    stageContent
                    if let rp = vm.renderProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server rendering preview… \(Int(rp * 100))%")
                                .font(.clipz(11, .bold)).foregroundStyle(Theme.coral)
                            ProgressView(value: max(rp, 0.05)).tint(Theme.coral)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: 0xE6090A0F))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
            }
        }
        .background(Theme.surface1)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder private var stageContent: some View {
        if vm.videoLoading {
            VStack(spacing: 8) {
                ProgressView().tint(Theme.coral)
                Text("Streaming video from server…").font(.clipz(12)).foregroundStyle(Theme.textMuted)
            }
        } else if let err = vm.videoError {
            Text(err).font(.clipz(12)).foregroundStyle(Theme.red).multilineTextAlignment(.center).padding(16)
        } else if let f = activeFile, FileManager.default.fileExists(atPath: f.path) {
            LoopingVideoView(holder: vm.loopingPlayer(for: f))
        } else {
            VStack(spacing: 4) {
                Text(vm.videoSourceMode == "render" ? "No render yet" : "Tap Original to load source")
                    .font(.clipz(13, .semibold)).foregroundStyle(Theme.textWhite)
                Text("Send an edit prompt below or switch to 'Original' to watch the uploaded video.")
                    .font(.clipz(11.5)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            }.padding(16)
        }
    }
}

struct StageChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.clipz(11, selected ? .bold : .medium)).foregroundStyle(selected ? Theme.textWhite : Theme.textMuted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.coral.opacity(0.18) : Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.coral : Theme.border))
        }.buttonStyle(.plain)
    }
}

// MARK: - Tab 1: AI Director

struct StudioDirectorSection: View {
    @Bindable var vm: ClipzViewModel
    let isKeyboardOpen: Bool
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if vm.feed.isEmpty {
                            QuickStartRecipesCard(
                                onMyStyle: { vm.requestMyStyle() },
                                onBrainstorm: {
                                    vm.mode = "brainstorm"
                                    vm.runBrainstorm("What's the best hook, pacing, and visual style for this reel?")
                                },
                                onQuickEdit: { vm.mode = "edit"; vm.runEdit($0) })
                        }
                        ForEach(vm.feed) { item in
                            feedRow(item).id(item.id)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.feed.count) { scrollToEnd(proxy) }
                .onChange(of: isKeyboardOpen) { scrollToEnd(proxy) }
            }

            composer
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = vm.feed.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    @ViewBuilder private func feedRow(_ item: FeedItem) -> some View {
        switch item {
        case .message(_, let role, let text, let badges, let isError):
            FeedMessageBubble(role: role, text: text, badges: badges, isError: isError)
        case .finalPrompt(_, let prompt):
            FinalPromptCardUI(prompt: prompt, busy: vm.busy,
                              onSend: { vm.mode = "edit"; vm.runEdit(prompt) },
                              onEditFirst: { vm.mode = "edit"; vm.composerInput = prompt })
        case .style(let id, let note, let prompt, let habits, let submitted):
            StyleCardUI(cardId: id, note: note, prompt: prompt, habits: habits, submitted: submitted, busy: vm.busy,
                        onSend: { p in
                            composerFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            vm.submitStylePrompt(cardId: id, editedPrompt: p)
                        },
                        onDiscard: { vm.discardCard(id) })
        case .plan(_, let plan):
            PlanCardUI(plan: plan)
        case .toolStep(_, _, let name, let args, let status, let result):
            ToolStepPill(name: name, args: args, status: status, result: result)
        case .ask(let id, let question, let options, let selected):
            AskCardUI(question: question, options: options, selected: selected, busy: vm.busy) { vm.answerAskCard(id, option: $0) }
        case .critic(_, let score, let issues):
            CriticCardUI(score: score, issues: issues)
        case .credits(_, let credits):
            CreditsCardUI(credits: credits, onCopy: { vm.showNotice("Credits copied!") })
        }
    }

    private var composer: some View {
        let accent = vm.mode == "brainstorm" ? Theme.blue : Theme.coral
        let canSend = !vm.busy && !vm.composerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let send = {
            guard canSend else { return }
            let text = vm.composerInput
            composerFocused = false
            vm.sendText(text)
        }
        return VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ComposerModeChip(label: "✻ Brainstorm", active: vm.mode == "brainstorm", brush: Theme.brainstormGradient) { vm.mode = "brainstorm" }
                    ComposerModeChip(label: "● Edit", active: vm.mode == "edit", brush: Theme.accentGradient) { vm.mode = "edit" }
                    Button { vm.requestMyStyle() } label: {
                        Text(vm.styleLoading ? "✦ Learning…" : "✦ My style")
                            .font(.clipz(12, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(Theme.styleGradient, in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(vm.busy || vm.styleLoading)

                    if isKeyboardOpen {
                        Button { composerFocused = false } label: {
                            Text("Done ▾").font(.clipz(11, .semibold)).foregroundStyle(Theme.textMuted)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.surface2, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border))
                        }.buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                StyledCapsuleInput(
                    text: $vm.composerInput,
                    placeholder: vm.mode == "brainstorm" ? "What should this reel feel like?" : "Tell the Director what to do…",
                    accent: accent, singleLine: false, maxLines: 4, onSend: send, focus: $composerFocused)

                Button(action: send) {
                    ZStack {
                        Circle().fill(!canSend ? Theme.disabledGradient : (vm.mode == "brainstorm" ? Theme.brainstormGradient : Theme.accentGradient))
                        if vm.busy {
                            ProgressView().tint(Theme.textWhite).scaleEffect(0.8)
                        } else {
                            VectorIcon(kind: .send, size: 18, color: canSend ? Theme.ink : Theme.textMuted)
                        }
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain).disabled(!canSend)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface1)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct ComposerModeChip: View {
    let label: String
    let active: Bool
    let brush: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.clipz(12, active ? .heavy : .semibold)).foregroundStyle(active ? Theme.ink : Theme.textMuted)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background {
                    if active { Capsule().fill(brush) } else { Capsule().fill(Theme.surface2).overlay(Capsule().stroke(Theme.border)) }
                }
        }.buttonStyle(.plain)
    }
}

struct QuickStartRecipesCard: View {
    let onMyStyle: () -> Void
    let onBrainstorm: () -> Void
    let onQuickEdit: (String) -> Void

    var body: some View {
        Card(radius: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("1-Tap AI Editing Recipes").font(.clipz(14.5, .bold)).foregroundStyle(Theme.textWhite)
                Text("Tap any recipe below to start immediately, or type in the box at the bottom:")
                    .font(.clipz(12)).foregroundStyle(Theme.textMuted)
                RecipeRow(tag: "✦ MY STYLE", color: Theme.violet, title: "Draft edit from my past reels (Review habits before sending)", action: onMyStyle)
                RecipeRow(tag: "✻ BRAINSTORM", color: Theme.blue, title: "Brainstorm hook ideas & pacing safely (no edits made yet)", action: onBrainstorm)
                RecipeRow(tag: "● AUTO EDIT", color: Theme.coral, title: "Remove silences, add dynamic word captions & upbeat music") {
                    onQuickEdit("Remove pauses, add viral captions, punch-in zoom on key words, and add upbeat background music.")
                }
                RecipeRow(tag: "● CALLOUTS", color: Theme.coral, title: "Add brand/tool logos on keywords + whoosh transitions") {
                    onQuickEdit("Add logos when tools or brands are named, add punch-in zooms on key moments, and add whoosh SFX.")
                }
            }
            .padding(14)
        }
    }
}

struct RecipeRow: View {
    let tag: String
    let color: Color
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(tag).font(.clipz(10, .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.45)))
                Text(title).font(.clipz(12.5)).foregroundStyle(Theme.textWhite).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("→").font(.clipz(14, .bold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }.buttonStyle(.plain)
    }
}

// MARK: - Feed cards

struct FeedMessageBubble: View {
    let role: String
    let text: String
    let badges: [String]
    let isError: Bool

    var body: some View {
        switch role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(text).font(.clipz(13.5)).foregroundStyle(Theme.textWhite).padding(12)
                    .background(Theme.coral.opacity(0.18),
                                in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16)
                        .stroke(Theme.coral.opacity(0.5)))
            }
        case "brain":
            Card(radius: 14, stroke: Theme.blue.opacity(0.45)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("✻ BRAINSTORM PARTNER").font(.clipz(10.5, .heavy)).foregroundStyle(Theme.blue)
                    Text(text).font(.clipz(13.5)).foregroundStyle(Theme.textWhite).lineSpacing(4)
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            }
        case "assistant":
            Card(radius: 14, stroke: Theme.coral.opacity(0.45)) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("● CLIPZ DIRECTOR").font(.clipz(10.5, .heavy)).foregroundStyle(Theme.coral)
                    Text(text).font(.clipz(13.5)).foregroundStyle(Theme.textWhite).lineSpacing(4)
                    if !badges.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(badges.enumerated()), id: \.offset) { _, name in
                                    Text("✓ \(name)").font(.clipz(10, .bold, mono: true)).foregroundStyle(Theme.green)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                                }
                            }
                        }
                    }
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            Text(text).font(.clipz(12)).foregroundStyle(isError ? Color(hex: 0xFFFFB4AB) : Theme.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isError ? Color(hex: 0xFF2F1518) : Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isError ? Theme.red.opacity(0.4) : Theme.border))
        }
    }
}

struct FinalPromptCardUI: View {
    let prompt: String
    let busy: Bool
    let onSend: () -> Void
    let onEditFirst: () -> Void

    var body: some View {
        Card(radius: 16, stroke: Theme.coral, lineWidth: 1.5) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FINAL PROMPT READY").font(.clipz(11, .heavy)).foregroundStyle(Theme.coral)
                Text(prompt).font(.clipz(13)).foregroundStyle(Theme.textWhite).padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                HStack(spacing: 8) {
                    FilledButton(title: "Send to Director", enabled: !busy, action: onSend)
                    OutlinedBtn(title: "Edit First", enabled: !busy, action: onEditFirst)
                }
            }
            .padding(14)
        }
    }
}

struct StyleCardUI: View {
    let cardId: String
    let note: String
    let prompt: String?
    let habits: [StyleHabit]
    let submitted: Bool
    let busy: Bool
    let onSend: (String) -> Void
    let onDiscard: () -> Void

    @State private var draft = ""
    @State private var activeRule: String?

    var body: some View {
        Card(radius: 16, stroke: Theme.violet, lineWidth: 1.5) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("✦ YOUR STYLE").font(.clipz(11, .heavy)).foregroundStyle(Theme.violet)
                    Spacer()
                    if submitted { Text("SENT ✓").font(.clipz(11, .bold)).foregroundStyle(Theme.green) }
                }
                Text(note).font(.clipz(12.5)).foregroundStyle(Theme.textWhite)

                if !habits.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(habits, id: \.self) { h in
                                Button { activeRule = activeRule == h.instruction ? nil : h.instruction } label: {
                                    Text("\(h.label) · \(Int(h.share * 100))%").font(.clipz(11, .semibold)).foregroundStyle(Theme.textWhite)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Theme.violet.opacity(0.16), in: Capsule())
                                        .overlay(Capsule().stroke(Theme.violet.opacity(0.45)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let rule = activeRule, !rule.isEmpty {
                        Text("Habit rule: \(rule)").font(.clipz(11.5)).foregroundStyle(Theme.violet)
                    }
                }

                if prompt != nil {
                    StyledCapsuleInput(text: Binding(get: { draft }, set: { if $0.count <= 2000 { draft = $0 } }),
                                       placeholder: "Customize style prompt…", accent: Theme.violet, maxLines: 5)
                    if !submitted {
                        HStack(spacing: 8) {
                            FilledButton(title: "Send to Director", enabled: !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSend(draft) }
                            OutlinedBtn(title: "Discard", color: Theme.textMuted, enabled: !busy, action: onDiscard)
                        }
                    }
                }
            }
            .padding(14)
        }
        .animation(.easeInOut(duration: 0.2), value: activeRule)
        .onAppear { draft = prompt ?? "" }
    }
}

struct PlanCardUI: View {
    let plan: EditPlan

    var body: some View {
        Card(radius: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("DIRECTOR EDIT PLAN").font(.clipz(10.5, .heavy)).foregroundStyle(Theme.coral)
                if !plan.summary.isEmpty {
                    Text(plan.summary).font(.clipz(13, .semibold)).foregroundStyle(Theme.textWhite)
                }
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").font(.clipz(12, .bold)).foregroundStyle(Theme.coral)
                        Text(s).font(.clipz(12.5)).foregroundStyle(Theme.textWhite)
                    }
                }
                if !plan.moments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(plan.moments, id: \.self) { m in
                                Text("\(m.atWord) → \(m.show)").font(.clipz(11, mono: true)).foregroundStyle(Theme.textWhite)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                            }
                        }
                    }
                }
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToolStepPill: View {
    let name: String
    let args: String
    let status: String
    let result: String?

    var body: some View {
        let dot = status == "ok" ? Theme.green : status == "fail" ? Theme.red : Theme.yellow
        Card(radius: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(dot).frame(width: 8, height: 8)
                    Text(name).font(.clipz(11.5, .bold, mono: true)).foregroundStyle(Theme.textWhite)
                    if !args.isEmpty {
                        Text(args).font(.clipz(10.5, mono: true)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                }
                if let result, !result.isEmpty {
                    Text("⎿ \(result)").font(.clipz(11, mono: true))
                        .foregroundStyle(status == "fail" ? Theme.red : Theme.textMuted)
                        .padding(.leading, 15)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AskCardUI: View {
    let question: String
    let options: [String]
    let selected: String?
    let busy: Bool
    let onPick: (String) -> Void

    var body: some View {
        Card(radius: 14, stroke: Theme.blue) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DIRECTOR QUESTION").font(.clipz(10.5, .heavy)).foregroundStyle(Theme.blue)
                Text(question).font(.clipz(13)).foregroundStyle(Theme.textWhite)
                ForEach(options, id: \.self) { opt in
                    Button { onPick(opt) } label: {
                        Text(opt).font(.clipz(12)).foregroundStyle(Theme.textWhite)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                            .opacity(busy || selected != nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain).disabled(busy || selected != nil)
                }
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CriticCardUI: View {
    let score: String
    let issues: [String]

    var body: some View {
        Card(radius: 14, stroke: Theme.green.opacity(0.45)) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CRITIC · \(score)/10").font(.clipz(11, .heavy)).foregroundStyle(Theme.green)
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text("• \(issue)").font(.clipz(12)).foregroundStyle(Theme.textWhite)
                }
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CreditsCardUI: View {
    let credits: [String]
    let onCopy: () -> Void

    var body: some View {
        let joined = credits.joined(separator: "\n")
        Card(radius: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CREDITS FOR YOUR CAPTION").font(.clipz(10.5, .heavy)).foregroundStyle(Theme.coral)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = joined
                        onCopy()
                    } label: {
                        Text("Copy").font(.clipz(11.5, .bold)).foregroundStyle(Theme.coral)
                    }.buttonStyle(.plain)
                }
                Text(joined).font(.clipz(11.5, mono: true)).foregroundStyle(Theme.textMuted)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tab 2: Interactive word subtitles

struct StudioTranscriptSection: View {
    @Bindable var vm: ClipzViewModel

    var body: some View {
        VStack(spacing: 10) {
            Card(radius: 12) {
                Text("Tap any spoken word below to insert its word ID (e.g. w64, w138) into your Director prompt.")
                    .font(.clipz(12)).foregroundStyle(Theme.textMuted).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }

            if vm.words.isEmpty {
                Spacer()
                Text("No transcript yet.").font(.clipz(13)).foregroundStyle(Theme.textMuted)
                Spacer()
            } else {
                let chunks = stride(from: 0, to: vm.words.count, by: 7).map { Array(vm.words[$0..<min($0 + 7, vm.words.count)]) }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chunks, id: \.first?.id) { line in
                            Card(radius: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(format: "%.1fs", line[0].start)).font(.clipz(11, .bold, mono: true)).foregroundStyle(Theme.coral)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(line) { w in
                                                Button { vm.insertWordId(w.id, text: w.text) } label: {
                                                    (Text(w.text + " ").font(.clipz(13)).foregroundColor(Theme.textWhite)
                                                     + Text(w.id).font(.clipz(9.5, .bold, mono: true)).foregroundColor(Theme.coral).baselineOffset(5))
                                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                                                }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Tab 3: Timeline

struct StudioTimelineSection: View {
    @Bindable var vm: ClipzViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    OutlinedBtn(title: "↶ Undo", size: 12, weight: .semibold, enabled: !vm.busy) { vm.performUndo() }
                    OutlinedBtn(title: "↷ Redo", size: 12, weight: .semibold, enabled: !vm.busy) { vm.performRedo() }
                    Spacer()
                    FilledButton(title: "Export", enabled: !vm.busy) { vm.runEdit("export the final video") }
                }

                Card(radius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TIMELINE SUMMARY").font(.clipz(11, .heavy)).foregroundStyle(Theme.coral)
                            Spacer()
                            if let src = vm.sourceVideo {
                                let w = src.width.map(String.init) ?? "?"
                                let h = src.height.map(String.init) ?? "?"
                                let d = src.durationS.map { String(format: "%.1fs", $0) } ?? ""
                                Text("\(w)×\(h) · \(d)").font(.clipz(11, mono: true)).foregroundStyle(Theme.textMuted)
                            }
                        }
                        Text(vm.summary).font(.clipz(12, mono: true)).foregroundStyle(Theme.textWhite).lineSpacing(4)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("RENDERS (\(vm.renders.count))").font(.clipz(11, .bold)).foregroundStyle(Theme.textMuted)
                if vm.renders.isEmpty {
                    Text("Nothing rendered yet.").font(.clipz(12.5)).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(vm.renders) { r in
                        Card(radius: 12) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(r.profile).font(.clipz(13, .bold)).foregroundStyle(Theme.textWhite)
                                        StatusPill(status: r.status)
                                    }
                                    Text(formatTimestamp(r.createdAt)).font(.clipz(11)).foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                if let url = r.url {
                                    OutlinedBtn(title: "▶ Play", color: Theme.coral, stroke: Theme.coral, size: 11.5, weight: .bold, radius: 8) {
                                        vm.playRenderVideo(url)
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}
