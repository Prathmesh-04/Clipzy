import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Picked movie -> temp file

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked_\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

// MARK: - Root

struct ClipzStudioRoot: View {
    @State private var vm = ClipzViewModel()
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var isKeyboardOpen = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isKeyboardOpen {
                    StudioTopBar(
                        inStudio: vm.inStudio && vm.selected != nil,
                        selectedProject: vm.selected,
                        serverHealthy: vm.serverHealthy,
                        onBackToReels: { Haptics.tap(); vm.inStudio = false },
                        onOpenGuide: { Haptics.tap(); showGuide = true },
                        onOpenSettings: { Haptics.tap(); showSettings = true }
                    )
                }

                if let err = vm.error {
                    ErrorStrip(text: err) { vm.clearError() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !vm.inStudio || vm.selected == nil {
                    ReelsHomeScreen(vm: vm)
                } else {
                    UnifiedStudioScreen(vm: vm, isKeyboardOpen: isKeyboardOpen)
                }
            }

            // Notices float above the content instead of pushing the layout around.
            VStack {
                Spacer()
                if let notice = vm.bannerNotice {
                    Toast(text: notice) { vm.clearNotice() }
                        .padding(.horizontal, 16).padding(.bottom, isKeyboardOpen ? 12 : 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .allowsHitTesting(vm.bannerNotice != nil)

            if showSettings {
                WorkspaceDialog(currentKey: vm.key, currentUrl: vm.baseUrl,
                                onDismiss: { showSettings = false },
                                onSave: { k, u in vm.saveSettings(key: k, baseUrl: u); showSettings = false })
            }
            if showGuide {
                QuickHowToModal { showGuide = false }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.yellow)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.ui(16, .bold))
            }
        }
        .onAppear { vm.loadProjects() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardOpen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardOpen = false }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.bannerNotice)
        .animation(.easeOut(duration: 0.2), value: vm.error)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .animation(.easeInOut(duration: 0.2), value: showGuide)
    }
}

// MARK: - Top bar, toast, error strip

struct StudioTopBar: View {
    let inStudio: Bool
    let selectedProject: Project?
    let serverHealthy: Bool?
    let onBackToReels: () -> Void
    let onOpenGuide: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if inStudio, let project = selectedProject {
                Button(action: onBackToReels) {
                    HStack(spacing: 6) {
                        VectorIcon(kind: .back, size: 14, color: Theme.white)
                        Text("Reels").font(.ui(13.5, .bold)).foregroundStyle(Theme.white)
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(Theme.ink.opacity(0.35), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Back to reels")

                HStack(spacing: 8) {
                    Circle().fill(Theme.statusColor(project.status)).frame(width: 8, height: 8)
                    Text(project.name).font(.display(13, .bold)).foregroundStyle(Theme.white).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Wordmark()
                Spacer(minLength: 0)
            }

            Button(action: onOpenGuide) {
                Text("Guide").font(.display(11, .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).frame(height: 38)
            }
            .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.ink, offset: 3))
            .accessibilityLabel("How to use ClipZ")

            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Circle().fill(serverHealthy == true ? Theme.green : serverHealthy == false ? Theme.red : Theme.yellow)
                        .frame(width: 8, height: 8)
                    VectorIcon(kind: .gear, size: 13, color: Theme.white)
                }
                .padding(.horizontal, 12).frame(height: 38)
                .background(Theme.ink.opacity(0.35), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(serverHealthy == true ? "Server connected. Open settings" : "Server not connected. Open settings")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.cobalt)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.14)).frame(height: 1) }
    }
}

struct Wordmark: View {
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 0) {
            Text("Clip").foregroundStyle(Theme.white)
            Text("Z").foregroundStyle(Theme.yellow)
        }
        .font(.display(size, .black)).tracking(-size * 0.04)
    }
}

struct ErrorStrip: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!").font(.mono(12, .bold)).foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20).background(Theme.red, in: Circle())
            Text(text).font(.ui(13.5, .medium)).foregroundStyle(Theme.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                VectorIcon(kind: .close, size: 18, color: Theme.paper.opacity(0.8))
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: 0xFF3A1620))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.red.opacity(0.5)).frame(height: 1) }
    }
}

struct Toast: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("✦").foregroundStyle(Theme.cobalt)
            Text(text).font(.ui(14, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.paper, in: Capsule())
        .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
        .background(Capsule().fill(Theme.cobalt).offset(x: 3, y: 3))
        .onTapGesture(perform: onDismiss)
    }
}

// MARK: - Screen A: Reels home hub

struct ReelsHomeScreen: View {
    @Bindable var vm: ClipzViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSourceChoice = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero

                MarqueeTape()
                    .rotationEffect(.degrees(-1.2))
                    .scaleEffect(x: 1.05)
                    .padding(.top, 22)
                    .zIndex(2)

                reelsSection
                    .padding(.top, 28)
            }
        }
        .background(Theme.ink)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { vm.loadProjects() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                        vm.uploadVideo(fileURL: movie.url, fileName: movie.url.lastPathComponent)
                    }
                } catch {
                    vm.error = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Hero + upload card

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            Theme.cobalt
            DotPattern()
            VStack(alignment: .leading, spacing: 18) {
                Text("AGENTIC REEL EDITOR · 9:16 · UP TO 90 S")
                    .font(.mono(10.5, .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: -2) {
                    HStack(spacing: 10) {
                        Text("You").foregroundStyle(Theme.yellow)
                        Text("talk.").foregroundStyle(Theme.white)
                    }
                    Text("It cuts.").foregroundStyle(Theme.white)
                }
                .font(.display(50, .black)).tracking(-1.5)
                .lineLimit(1).minimumScaleFactor(0.6)

                Text("Upload a raw vertical video and say what you want in plain words. ClipZ cuts the dead air, adds captions, memes and music, then renders your reel.")
                    .font(.ui(15.5)).foregroundStyle(.white.opacity(0.92)).lineSpacing(3)

                uploadCard
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 34)
        }
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.cobalt)
                    VectorIcon(kind: .upload, size: 20, color: Theme.yellow)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New reel").font(.display(18, .bold)).foregroundStyle(Theme.ink)
                    Text("We analyse it as soon as it lands.")
                        .font(.ui(13)).foregroundStyle(Theme.ink.opacity(0.65))
                }
            }

            StyledCapsuleInput(
                text: Binding(get: { vm.newReelName }, set: { if $0.count <= 120 { vm.newReelName = $0 } }),
                placeholder: "Reel name (optional)", singleLine: true, light: true)

            Button {
                Haptics.tap()
                showSourceChoice = true
            } label: {
                HStack(spacing: 10) {
                    if vm.busy && vm.uploadProgress == nil {
                        ProgressView().tint(Theme.ink)
                    } else {
                        VectorIcon(kind: .upload, size: 18, color: Theme.ink)
                    }
                    Text(vm.uploadProgress != nil
                         ? (vm.uploadStatusText.isEmpty ? "Uploading…" : vm.uploadStatusText)
                         : "Select video & upload")
                        .font(.display(14, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .opacity(vm.busy ? 0.6 : 1)
            }
            .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.ink, stroke: Theme.ink))
            .disabled(vm.busy)
            .padding(.trailing, 4).padding(.bottom, 4)
            .confirmationDialog("Choose video source", isPresented: $showSourceChoice, titleVisibility: .visible) {
                Button("Files (Downloads, iCloud…)") { showFileImporter = true }
                Button("Photo Library") { showPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .videos)
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent("picked_\(UUID().uuidString)")
                            .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
                        try FileManager.default.copyItem(at: url, to: dest)
                        vm.uploadVideo(fileURL: dest, fileName: url.lastPathComponent)
                    } catch {
                        vm.error = "Could not read selected video: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    vm.error = "Could not open file: \(error.localizedDescription)"
                }
            }

            if let p = vm.uploadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.lineLight)
                            Capsule().fill(Theme.cobalt).frame(width: max(8, geo.size.width * p))
                        }
                    }
                    .frame(height: 8)
                    Text("Keep the app open while uploading").font(.mono(11)).foregroundStyle(Theme.ink.opacity(0.55))
                }
                .animation(.easeOut(duration: 0.2), value: p)
            }
        }
        .padding(20)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.ink, lineWidth: 2))
        .hardShadow(Theme.ink, offset: 6, radius: 26)
    }

    // MARK: Reels list

    private var reelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Workspace", color: Theme.yellow)
                    HStack(spacing: 10) {
                        Text("Your reels").font(.display(26, .black)).tracking(-0.8).foregroundStyle(Theme.paper)
                        Text("\(vm.projects.count)").font(.mono(13, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Theme.yellow, in: Capsule())
                    }
                }
                Spacer()
                Button { Haptics.tap(); vm.loadProjects() } label: {
                    Text("Refresh ↻").font(.mono(12, .bold)).foregroundStyle(Theme.yellow)
                        .padding(.horizontal, 6).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if vm.projects.isEmpty {
                emptyState
            } else {
                ForEach(vm.projects) { proj in
                    Button { Haptics.tap(); vm.openProjectInStudio(proj) } label: { ProjectRow(project: proj) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cobalt)
                VectorIcon(kind: .play, size: 22, color: Theme.yellow)
            }
            .frame(width: 56, height: 56)
            Text(vm.serverHealthy == false ? "Can't reach the server" : "No reels yet")
                .font(.display(16, .bold)).foregroundStyle(Theme.paper)
            Text(vm.serverHealthy == false
                 ? "Check the API URL in settings (gear icon), then pull down to refresh."
                 : "Upload your first video above. It shows up here once the server has it.")
                .font(.ui(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 6])))
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        Card(radius: 22) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cobalt)
                    VectorIcon(kind: .play, size: 18, color: Theme.yellow)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.ui(17, .bold)).foregroundStyle(Theme.paper).lineLimit(1)
                    HStack(spacing: 8) {
                        StatusPill(status: project.status)
                        Text(formatTimestamp(project.createdAt)).font(.mono(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("→").font(.display(18, .bold)).foregroundStyle(Theme.yellow)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this reel in the studio")
    }
}

// MARK: - Modals (paper cards, like the site's light sections)

struct DialogOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture(perform: onDismiss)
            ScrollView {
                content()
                    .padding(22)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.ink, lineWidth: 2))
                    .hardShadow(Theme.cobalt, offset: 6, radius: 28)
                    .padding(.horizontal, 22).padding(.vertical, 44)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
    }
}

struct WorkspaceDialog: View {
    let currentKey: String
    let currentUrl: String
    let onDismiss: () -> Void
    let onSave: (String, String) -> Void

    @State private var newKey: String
    @State private var newUrl: String

    init(currentKey: String, currentUrl: String, onDismiss: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.currentKey = currentKey
        self.currentUrl = currentUrl
        self.onDismiss = onDismiss
        self.onSave = onSave
        _newKey = State(initialValue: currentKey)
        _newUrl = State(initialValue: currentUrl)
    }

    var body: some View {
        DialogOverlay(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Connection", color: Theme.cobalt)
                Text("Workspace & API").font(.display(22, .black)).tracking(-0.5).foregroundStyle(Theme.ink)
                Text("Keep 'reelforge-dev-key' to see your existing projects, or type any new name for a fresh workspace.")
                    .font(.ui(14)).foregroundStyle(Theme.ink.opacity(0.7))

                labelled("WORKSPACE KEY") { StyledCapsuleInput(text: $newKey, placeholder: "Workspace Key", singleLine: true, light: true) }
                labelled("API BASE URL") { StyledCapsuleInput(text: $newUrl, placeholder: "API Base URL", singleLine: true, light: true) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        suggestion("Use default server") { newUrl = ClipzConfig.baseURL }
                        suggestion("Default key") { newKey = ClipzConfig.workspaceKey }
                    }
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Cancel").font(.ui(15, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                            .padding(.horizontal, 14).frame(height: 46).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { Haptics.tap(); onSave(newKey, newUrl) } label: {
                        Text("Save & connect").font(.display(13, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20).frame(height: 46)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.ink, stroke: Theme.ink))
                    .padding([.trailing, .bottom], 4)
                }
                .padding(.top, 4)
            }
        }
    }

    private func labelled<V: View>(_ label: String, @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.mono(10.5, .bold)).tracking(1.2).foregroundStyle(Theme.ink.opacity(0.55))
            field()
        }
    }

    private func suggestion(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(label).font(.ui(13, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).frame(height: 38)
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

struct QuickHowToModal: View {
    let onDismiss: () -> Void

    var body: some View {
        DialogOverlay(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Quick guide", color: Theme.cobalt)
                Text("You talk.\nIt cuts.").font(.display(26, .black)).tracking(-0.8).foregroundStyle(Theme.ink)
                HowToStep(num: "01", title: "Pick a reel",
                          text: "Open a reel from your list, or upload a new video from Files or Photos.")
                HowToStep(num: "02", title: "Brainstorm, My style or Edit",
                          text: "✻ Brainstorm talks the edit through without touching the timeline.\n✦ My style drafts a prompt from your past reels.\n● Edit streams the Director's tool calls and renders a preview.")
                HowToStep(num: "03", title: "Fine-tune and save",
                          text: "Subtitles: tap any word to drop its ID into your prompt.\nTimeline: undo, redo or export.\nSave MP4: puts the render in your Photos library.")
                HStack {
                    Spacer()
                    Button { Haptics.tap(); onDismiss() } label: {
                        Text("Got it").font(.display(13, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 24).frame(height: 46)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: Theme.ink, stroke: Theme.ink))
                    .padding([.trailing, .bottom], 4)
                }
            }
        }
    }
}

struct HowToStep: View {
    let num: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.ink).frame(height: 3)
            Text(num).font(.mono(12, .bold)).foregroundStyle(Theme.cobalt)
            Text(title).font(.display(15, .bold)).foregroundStyle(Theme.ink)
            Text(text).font(.ui(14)).foregroundStyle(Theme.ink.opacity(0.75)).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
