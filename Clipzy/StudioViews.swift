import SwiftUI
import AVKit

// MARK: - Screen B: Unified studio workspace

struct UnifiedStudioScreen: View {
    @Bindable var vm: ClipzViewModel
    let isKeyboardOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Hidden while the keyboard is up so the prompt box gets the room.
            if !isKeyboardOpen {
                StudioVideoStage(vm: vm)
            }

            HStack(spacing: 6) {
                WorkspaceTabButton(title: "Director", badge: nil, selected: vm.studioTab == "director") { vm.studioTab = "director" }
                WorkspaceTabButton(title: "Subtitles", badge: vm.words.isEmpty ? nil : "\(vm.words.count)",
                                   selected: vm.studioTab == "transcript") { vm.studioTab = "transcript" }
                WorkspaceTabButton(title: "Timeline", badge: "v\(vm.timelineVersion)",
                                   selected: vm.studioTab == "timeline") { vm.studioTab = "timeline" }
            }
            .padding(6)
            .background(Theme.ink2, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.studioTab)

            Group {
                switch vm.studioTab {
                case "transcript": StudioTranscriptSection(vm: vm)
                case "timeline": StudioTimelineSection(vm: vm)
                default: StudioDirectorSection(vm: vm, isKeyboardOpen: isKeyboardOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.ink)
    }
}

struct WorkspaceTabButton: View {
    let title: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.display(11.5, selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                if let badge {
                    Text(badge).font(.mono(10, .bold)).foregroundStyle(selected ? Theme.yellow : Theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(selected ? Theme.ink : Theme.ink3, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity).frame(height: 38)
            .background(selected ? Theme.yellow : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                StageChip(label: vm.renders.isEmpty ? "Result" : "Render · \(vm.renders[0].profile)",
                          selected: vm.videoSourceMode == "render") { vm.videoSourceMode = "render" }
                StageChip(label: "Original", selected: vm.videoSourceMode == "original") {
                    vm.videoSourceMode = "original"
                    vm.loadOriginalVideo()
                }
                Spacer(minLength: 4)

                if let f = activeFile, FileManager.default.fileExists(atPath: f.path) {
                    Button {
                        Haptics.tap()
                        vm.saveCurrentVideoToPhotos()
                    } label: {
                        HStack(spacing: 6) {
                            VectorIcon(kind: .download, size: 13, color: Theme.ink)
                            Text("Save MP4").font(.display(10.5, .bold)).foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 12).frame(height: 34)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.cobalt, offset: 3))
                    .accessibilityLabel("Save MP4 to Photos")
                }

                Button { Haptics.select(); withAnimation(.easeInOut(duration: 0.2)) { vm.videoExpanded.toggle() } } label: {
                    Text(vm.videoExpanded ? "Hide" : "Video").font(.mono(11, .bold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10).frame(height: 34)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, vm.videoExpanded ? 6 : 10)

            if vm.videoExpanded {
                ZStack {
                    Color.black
                    stageContent
                    if let rp = vm.renderProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RENDERING PREVIEW · \(Int(rp * 100))%")
                                .font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.yellow)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.18))
                                    Capsule().fill(Theme.yellow).frame(width: max(6, geo.size.width * max(rp, 0.05)))
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.ink.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 2))
                .hardShadow(Theme.cobalt, offset: 5, radius: 24)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(Theme.ink)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var stageContent: some View {
        if vm.videoLoading {
            VStack(spacing: 10) {
                ProgressView().tint(Theme.yellow)
                Text("Loading video…").font(.mono(12)).foregroundStyle(Theme.muted)
            }
        } else if let err = vm.videoError {
            VStack(spacing: 10) {
                Text(err).font(.ui(13)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
                GhostButton(title: "Try again") {
                    if vm.videoSourceMode == "render", let u = vm.playingRenderUrl { vm.playRenderVideo(u) } else { vm.loadOriginalVideo() }
                }
            }.padding(16)
        } else if let f = activeFile, FileManager.default.fileExists(atPath: f.path) {
            LoopingVideoView(holder: vm.loopingPlayer(for: f))
        } else {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Theme.cobalt)
                    VectorIcon(kind: .play, size: 18, color: Theme.yellow)
                }
                .frame(width: 44, height: 44)
                Text(vm.videoSourceMode == "render" ? "No render yet" : "Tap Original to load the source")
                    .font(.display(13, .bold)).foregroundStyle(Theme.paper)
                Text("Tell the Director what to do and the preview lands here.")
                    .font(.ui(12.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.padding(16)
        }
    }
}

struct StageChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(label).font(.mono(11, .bold)).foregroundStyle(selected ? Theme.ink : Theme.muted)
                .padding(.horizontal, 12).frame(height: 34)
                .background(selected ? Theme.paper : .clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.paper : Theme.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Tab 1: AI Director

struct StudioDirectorSection: View {
    @Bindable var vm: ClipzViewModel
    let isKeyboardOpen: Bool
    @FocusState private var composerFocused: Bool

    private var editSuggestions: [(String, String)] {
        [("Remove pauses", "Remove pauses and dead air."),
         ("Viral captions", "Add viral word-by-word captions."),
         ("Upbeat music", "Add upbeat background music, ducked under my voice."),
         ("Logos + whoosh", "Add logos when tools or brands are named, plus whoosh SFX."),
         ("Export", "export the final video")]
    }
    private let brainSuggestions = [("Best hook?", "What's the best hook for this reel?"),
                                    ("Pacing ideas", "How should I pace this reel?"),
                                    ("Caption style", "What caption style would suit this reel?")]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
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
                        if vm.busy && !vm.styleLoading {
                            HStack(spacing: 10) {
                                TypingDots()
                                Text(vm.mode == "brainstorm" ? "Thinking…" : "Director is working…")
                                    .font(.mono(12)).foregroundStyle(Theme.muted)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .id("typing")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.feed.count) { scrollToEnd(proxy) }
                .onChange(of: vm.busy) { scrollToEnd(proxy) }
                .onChange(of: isKeyboardOpen) { scrollToEnd(proxy) }
            }

            composer
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if vm.busy && !vm.styleLoading { proxy.scrollTo("typing", anchor: .bottom) }
            else if let last = vm.feed.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    @ViewBuilder private func feedRow(_ item: FeedItem) -> some View {
        switch item {
        case .message(_, let role, let text, let badges, let isError):
            FeedMessageBubble(role: role, text: text, badges: badges, isError: isError)
        case .finalPrompt(_, let prompt):
            FinalPromptCardUI(prompt: prompt, busy: vm.busy,
                              onSend: { vm.mode = "edit"; vm.runEdit(prompt) },
                              onEditFirst: { vm.mode = "edit"; vm.composerInput = prompt; composerFocused = true })
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
        let accent = vm.mode == "brainstorm" ? Theme.periwinkle : Theme.yellow
        let canSend = !vm.busy && !vm.composerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let send = {
            guard canSend else { return }
            Haptics.tap()
            let text = vm.composerInput
            composerFocused = false
            vm.sendText(text)
        }
        let suggestions = vm.mode == "brainstorm" ? brainSuggestions : editSuggestions

        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ComposerModeChip(label: "✻ Brainstorm", active: vm.mode == "brainstorm", fill: Theme.periwinkle) { vm.mode = "brainstorm" }
                    ComposerModeChip(label: "● Edit", active: vm.mode == "edit", fill: Theme.yellow) { vm.mode = "edit" }
                    Button {
                        Haptics.tap()
                        vm.requestMyStyle()
                    } label: {
                        Text(vm.styleLoading ? "✦ Learning…" : "✦ My style")
                            .font(.ui(13.5, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Theme.paper, in: Capsule())
                            .opacity(vm.busy || vm.styleLoading ? 0.5 : 1)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(vm.busy || vm.styleLoading)

                    if isKeyboardOpen {
                        Button { composerFocused = false } label: {
                            Text("Done ▾").font(.mono(11.5, .bold)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 12).frame(height: 36)
                                .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }

            if vm.composerInput.isEmpty && !vm.busy {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.0) { chip in
                            Button {
                                Haptics.select()
                                vm.composerInput = chip.1
                            } label: {
                                Text(chip.0).font(.ui(13, .medium)).foregroundStyle(Theme.paper.opacity(0.9))
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
                                    .contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                StyledCapsuleInput(
                    text: $vm.composerInput,
                    placeholder: vm.mode == "brainstorm" ? "What should this reel feel like?" : "Tell the Director what to do…",
                    accent: accent, singleLine: false, maxLines: 4, onSend: send, focus: $composerFocused)

                Button(action: send) {
                    ZStack {
                        if vm.busy {
                            ProgressView().tint(Theme.muted)
                        } else {
                            VectorIcon(kind: .send, size: 20, color: canSend ? Theme.ink : Theme.muted)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(BrutalButtonStyle(fill: canSend ? accent : Theme.ink3,
                                               shadow: canSend ? Theme.cobalt : .clear, offset: 3))
                .disabled(!canSend)
                .padding([.trailing, .bottom], 3)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 10)
        .background(Theme.ink2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1.5) }
        .animation(.easeOut(duration: 0.2), value: vm.composerInput.isEmpty)
    }
}

struct ComposerModeChip: View {
    let label: String
    let active: Bool
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(label).font(.ui(13.5, .bold)).foregroundStyle(active ? Theme.ink : Theme.muted)
                .padding(.horizontal, 14).frame(height: 36)
                .background(active ? fill : .clear, in: Capsule())
                .overlay(Capsule().stroke(active ? fill : Theme.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct QuickStartRecipesCard: View {
    let onMyStyle: () -> Void
    let onBrainstorm: () -> Void
    let onQuickEdit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "One-tap recipes", color: Theme.yellow)
            Text("Start with a recipe.\nOr just type.").font(.display(22, .black)).tracking(-0.6).foregroundStyle(Theme.paper)
            Text("Tap a recipe to start straight away, or write your own prompt in the box below.")
                .font(.ui(14)).foregroundStyle(Theme.muted)
            RecipeRow(tag: "✦ MY STYLE", color: Theme.paper, title: "Draft an edit from my past reels", sub: "Review the habits before it sends", action: onMyStyle)
            RecipeRow(tag: "✻ BRAINSTORM", color: Theme.periwinkle, title: "Hook ideas & pacing", sub: "No edits are made yet", action: onBrainstorm)
            RecipeRow(tag: "● AUTO EDIT", color: Theme.yellow, title: "Cut silences, add captions & music", sub: "Punch-in zooms on key words") {
                onQuickEdit("Remove pauses, add viral captions, punch-in zoom on key words, and add upbeat background music.")
            }
            RecipeRow(tag: "● CALLOUTS", color: Theme.yellow, title: "Logos on keywords + whooshes", sub: "Brand and tool names get a visual") {
                onQuickEdit("Add logos when tools or brands are named, add punch-in zooms on key moments, and add whoosh SFX.")
            }
        }
        .padding(.top, 6)
    }
}

struct RecipeRow: View {
    let tag: String
    let color: Color
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tag).font(.mono(10, .bold)).tracking(0.8).foregroundStyle(color)
                    Text(title).font(.ui(16, .bold)).foregroundStyle(Theme.paper).multilineTextAlignment(.leading)
                    Text(sub).font(.ui(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("→").font(.display(18, .bold)).foregroundStyle(color)
            }
            .padding(16)
            .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
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
                Spacer(minLength: 48)
                Text(text).font(.ui(15.5, .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Theme.yellow,
                                in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 5, topTrailingRadius: 20))
                    .textSelection(.enabled)
            }
        case "brain":
            Card(radius: 20, stroke: Theme.periwinkle.opacity(0.6)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✻ BRAINSTORM PARTNER").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.periwinkle)
                    Text(text).font(.ui(15.5)).foregroundStyle(Theme.paper).lineSpacing(4).textSelection(.enabled)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        case "assistant":
            Card(radius: 20, stroke: Theme.yellow.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("● CLIPZ DIRECTOR").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.yellow)
                    Text(text).font(.ui(15.5)).foregroundStyle(Theme.paper).lineSpacing(4).textSelection(.enabled)
                    if !badges.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(badges.enumerated()), id: \.offset) { _, name in
                                    Text("✓ \(name)").font(.mono(10.5, .bold)).foregroundStyle(Theme.green)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Theme.green.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("›").font(.mono(13, .bold)).foregroundStyle(isError ? Theme.red : Theme.yellow)
                Text(text).font(.mono(12.5)).foregroundStyle(isError ? Theme.red : Theme.muted).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct FinalPromptCardUI: View {
    let prompt: String
    let busy: Bool
    let onSend: () -> Void
    let onEditFirst: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FINAL PROMPT READY").font(.mono(10.5, .bold)).tracking(1.2).foregroundStyle(Theme.cobalt)
            Text(prompt).font(.ui(15)).foregroundStyle(Theme.ink).lineSpacing(3)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.lineLight, lineWidth: 1.5))
                .textSelection(.enabled)
            HStack(spacing: 10) {
                PrimaryButton(title: "Send to Director", enabled: !busy, action: onSend)
                    .padding([.trailing, .bottom], 4)
                GhostButton(title: "Edit first", color: Theme.ink, enabled: !busy, action: onEditFirst)
            }
        }
        .padding(18)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.ink, lineWidth: 2))
        .hardShadow(Theme.cobalt, offset: 5, radius: 24)
        .padding(.trailing, 5).padding(.bottom, 5)
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
        Card(radius: 24, stroke: Theme.paper, lineWidth: 2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("✦ YOUR STYLE").font(.mono(10.5, .bold)).tracking(1.2).foregroundStyle(Theme.paper)
                    Spacer()
                    if submitted { Text("SENT ✓").font(.mono(10.5, .bold)).foregroundStyle(Theme.green) }
                }
                Text(note).font(.ui(14.5)).foregroundStyle(Theme.paper)

                if !habits.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(habits, id: \.self) { h in
                                let on = activeRule == h.instruction
                                Button {
                                    Haptics.select()
                                    activeRule = on ? nil : h.instruction
                                } label: {
                                    Text("\(h.label) · \(Int(h.share * 100))%").font(.ui(12.5, .bold))
                                        .foregroundStyle(on ? Theme.ink : Theme.paper)
                                        .padding(.horizontal, 12).frame(height: 34)
                                        .background(on ? Theme.paper : .clear, in: Capsule())
                                        .overlay(Capsule().stroke(Theme.paper.opacity(0.6), lineWidth: 1.5))
                                        .contentShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let rule = activeRule, !rule.isEmpty {
                        Text("Habit rule: \(rule)").font(.ui(13)).foregroundStyle(Theme.muted)
                    }
                }

                if prompt != nil {
                    StyledCapsuleInput(text: Binding(get: { draft }, set: { if $0.count <= 2000 { draft = $0 } }),
                                       placeholder: "Customize style prompt…", accent: Theme.paper, maxLines: 5)
                    if !submitted {
                        HStack(spacing: 10) {
                            PrimaryButton(title: "Send to Director", enabled: !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                          shadow: Theme.cobalt) { onSend(draft) }
                                .padding([.trailing, .bottom], 4)
                            GhostButton(title: "Discard", color: Theme.muted, enabled: !busy, action: onDiscard)
                        }
                    }
                }
            }
            .padding(18)
        }
        .animation(.easeInOut(duration: 0.2), value: activeRule)
        .onAppear { draft = prompt ?? "" }
    }
}

struct PlanCardUI: View {
    let plan: EditPlan

    var body: some View {
        Card(radius: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text("DIRECTOR EDIT PLAN").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.yellow)
                if !plan.summary.isEmpty {
                    Text(plan.summary).font(.ui(15.5, .bold)).foregroundStyle(Theme.paper)
                }
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%02d", i + 1)).font(.mono(11.5, .bold)).foregroundStyle(Theme.yellow)
                        Text(s).font(.ui(14.5)).foregroundStyle(Theme.paper)
                    }
                }
                if !plan.moments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(plan.moments, id: \.self) { m in
                                Text("\(m.atWord) → \(m.show)").font(.mono(11.5)).foregroundStyle(Theme.paper)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Theme.ink3, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if status == "run" {
                    ProgressView().controlSize(.mini).tint(Theme.yellow)
                } else {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(name).font(.mono(12.5, .bold)).foregroundStyle(Theme.yellow)
                if !args.isEmpty {
                    Text(args).font(.mono(11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            if let result, !result.isEmpty {
                Text("⎿ \(result)").font(.mono(11.5)).foregroundStyle(status == "fail" ? Theme.red : Theme.green)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct AskCardUI: View {
    let question: String
    let options: [String]
    let selected: String?
    let busy: Bool
    let onPick: (String) -> Void

    var body: some View {
        Card(radius: 22, stroke: Theme.periwinkle, lineWidth: 2) {
            VStack(alignment: .leading, spacing: 10) {
                Text("DIRECTOR QUESTION").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.periwinkle)
                Text(question).font(.ui(15.5, .medium)).foregroundStyle(Theme.paper).lineSpacing(3)
                ForEach(options, id: \.self) { opt in
                    let chosen = selected == opt
                    Button {
                        Haptics.tap()
                        onPick(opt)
                    } label: {
                        Text(opt).font(.ui(14.5, .bold)).foregroundStyle(chosen ? Theme.ink : Theme.paper)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(chosen ? Theme.yellow : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(chosen ? Theme.yellow : Theme.line, lineWidth: 1.5))
                            .opacity(selected != nil && !chosen ? 0.4 : 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || selected != nil)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CriticCardUI: View {
    let score: String
    let issues: [String]

    var body: some View {
        Card(radius: 20, stroke: Theme.green.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("CRITIC").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.green)
                    Spacer()
                    Text(score).font(.display(22, .black)).foregroundStyle(Theme.green)
                    Text("/10").font(.mono(12)).foregroundStyle(Theme.muted)
                }
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.green)
                        Text(issue).font(.ui(14)).foregroundStyle(Theme.paper)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CreditsCardUI: View {
    let credits: [String]
    let onCopy: () -> Void

    var body: some View {
        let joined = credits.joined(separator: "\n")
        Card(radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CREDITS FOR YOUR CAPTION").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.yellow)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = joined
                        Haptics.success()
                        onCopy()
                    } label: {
                        Text("Copy").font(.ui(13, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(Theme.yellow, in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Text(joined).font(.mono(12)).foregroundStyle(Theme.muted).textSelection(.enabled)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tab 2: Interactive word subtitles

struct StudioTranscriptSection: View {
    @Bindable var vm: ClipzViewModel
    @State private var query = ""

    private var filtered: [Word] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return vm.words.filter { $0.text.lowercased().contains(q) || $0.id.lowercased() == q }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap a word to drop its ID (like w64) into your Director prompt.")
                    .font(.ui(14)).foregroundStyle(Theme.muted)
                if !vm.words.isEmpty {
                    StyledCapsuleInput(text: $query, placeholder: "Search words or IDs", singleLine: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if vm.words.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No transcript yet").font(.display(16, .bold)).foregroundStyle(Theme.paper)
                    Text("It appears once the video has been analysed.").font(.ui(14)).foregroundStyle(Theme.muted)
                }
                Spacer()
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView {
                    if filtered.isEmpty {
                        Text("No matches").font(.mono(12)).foregroundStyle(Theme.muted).padding(.top, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(filtered) { w in WordChip(word: w) { vm.insertWordId(w.id, text: w.text) } }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                let chunks = stride(from: 0, to: vm.words.count, by: 7).map { Array(vm.words[$0..<min($0 + 7, vm.words.count)]) }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(chunks, id: \.first?.id) { line in
                            Card(radius: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(format: "%.1fs", line[0].start)).font(.mono(11, .bold)).foregroundStyle(Theme.yellow)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(line) { w in WordChip(word: w) { vm.insertWordId(w.id, text: w.text) } }
                                        }
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }
}

struct WordChip: View {
    let word: Word
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            (Text(word.text + " ").font(.ui(15, .medium)).foregroundColor(Theme.paper)
             + Text(word.id).font(.mono(9.5, .bold)).foregroundColor(Theme.yellow).baselineOffset(5))
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Theme.ink3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Tab 3: Timeline

struct StudioTimelineSection: View {
    @Bindable var vm: ClipzViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    GhostButton(title: "↶ Undo", enabled: !vm.busy) { vm.performUndo() }
                    GhostButton(title: "↷ Redo", enabled: !vm.busy) { vm.performRedo() }
                    Spacer()
                    PrimaryButton(title: "Export", enabled: !vm.busy, shadow: Theme.cobalt) { vm.runEdit("export the final video") }
                        .padding([.trailing, .bottom], 4)
                }

                Card(radius: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("TIMELINE SUMMARY").font(.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.yellow)
                            Spacer()
                            if let src = vm.sourceVideo {
                                let w = src.width.map(String.init) ?? "?"
                                let h = src.height.map(String.init) ?? "?"
                                let d = src.durationS.map { String(format: "%.1fs", $0) } ?? ""
                                Text("\(w)×\(h) · \(d)").font(.mono(11)).foregroundStyle(Theme.muted)
                            }
                        }
                        Text(vm.summary).font(.mono(12.5)).foregroundStyle(Theme.paper).lineSpacing(5).textSelection(.enabled)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Eyebrow(text: "Renders", color: Theme.yellow)
                    Text("\(vm.renders.count)").font(.mono(11, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.yellow, in: Capsule())
                }

                if vm.renders.isEmpty {
                    Text("Nothing rendered yet. Ask the Director for an edit, or tap Export.")
                        .font(.ui(14)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(vm.renders) { r in
                        Card(radius: 20) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(r.profile).font(.display(14, .bold)).foregroundStyle(Theme.paper)
                                        StatusPill(status: r.status)
                                    }
                                    Text(formatTimestamp(r.createdAt)).font(.mono(10.5)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if let url = r.url {
                                    Button {
                                        Haptics.tap()
                                        vm.playRenderVideo(url)
                                    } label: {
                                        HStack(spacing: 6) {
                                            VectorIcon(kind: .play, size: 12, color: Theme.ink)
                                            Text("Play").font(.display(11, .bold)).foregroundStyle(Theme.ink)
                                        }
                                        .padding(.horizontal, 14).frame(height: 38)
                                    }
                                    .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.cobalt, offset: 3))
                                    .padding([.trailing, .bottom], 3)
                                }
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
        }
    }
}
