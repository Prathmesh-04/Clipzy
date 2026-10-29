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
            Theme.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isKeyboardOpen {
                    StudioTopBar(
                        inStudio: vm.inStudio,
                        selectedProject: vm.selected,
                        serverHealthy: vm.serverHealthy,
                        onBackToReels: { vm.inStudio = false },
                        onOpenGuide: { showGuide = true },
                        onOpenSettings: { showSettings = true }
                    )
                }

                if let err = vm.error {
                    AlertStrip(text: err, isError: true) { vm.clearError() }
                }
                if let notice = vm.bannerNotice {
                    AlertStrip(text: notice, isError: false) { vm.clearNotice() }
                }

                if !vm.inStudio || vm.selected == nil {
                    ReelsHomeScreen(vm: vm)
                } else {
                    UnifiedStudioScreen(vm: vm, isKeyboardOpen: isKeyboardOpen)
                }
            }

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
        .tint(Theme.coral)
        .onAppear { vm.loadProjects() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardOpen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardOpen = false }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.bannerNotice)
    }
}

// MARK: - Top bar & alerts

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
                        VectorIcon(kind: .back, size: 14, color: Theme.textWhite)
                        Text("Reels").font(.clipz(12, .semibold)).foregroundStyle(Theme.textWhite)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    Circle().fill(Theme.statusColor(project.status)).frame(width: 8, height: 8)
                    Text(project.name).font(.clipz(14, .bold)).foregroundStyle(Theme.textWhite).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.accentGradient)
                        VectorIcon(kind: .play, size: 14, color: Color(hex: 0xFF0B0C10))
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("ClipZ").font(.clipz(16, .heavy)).foregroundStyle(Theme.textWhite)
                            Text(" Studio").font(.clipz(16, .bold)).foregroundStyle(Theme.coral)
                        }
                        Text("AI Reel Director").font(.clipz(10.5)).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onOpenGuide) {
                Text("Guide").font(.clipz(11.5, .semibold)).foregroundStyle(Theme.blue)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .buttonStyle(.plain)

            Button(action: onOpenSettings) {
                HStack(spacing: 5) {
                    Circle().fill(serverHealthy == true ? Theme.green : serverHealthy == false ? Theme.red : Theme.yellow)
                        .frame(width: 7, height: 7)
                    VectorIcon(kind: .gear, size: 12, color: Theme.textMuted)
                    Text(serverHealthy == true ? "Live API" : "Server")
                        .font(.clipz(11, .semibold)).foregroundStyle(Theme.textWhite)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.surface1)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct AlertStrip: View {
    let text: String
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        let accent = isError ? Theme.red : Theme.green
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(text).font(.clipz(12)).foregroundStyle(Theme.textWhite)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Text("Dismiss").font(.clipz(11, .bold)).foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(isError ? Color(hex: 0xFF331619) : Color(hex: 0xFF132A20))
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
            LazyVStack(spacing: 18) {
                HStack(spacing: 8) {
                    StepPill(num: "1", label: "Pick Reel", active: true)
                    StepPill(num: "2", label: "AI Direct / Style", active: false)
                    StepPill(num: "3", label: "Preview & Save", active: false)
                }

                uploadCard

                HStack {
                    Text("Workspace Projects (\(vm.projects.count))")
                        .font(.clipz(16, .bold)).foregroundStyle(Theme.textWhite)
                    Spacer()
                    Button { vm.loadProjects() } label: {
                        Text("Refresh").font(.clipz(12.5, .semibold)).foregroundStyle(Theme.coral)
                    }
                    .buttonStyle(.plain)
                }

                if vm.projects.isEmpty {
                    Card(radius: 16) {
                        VStack(spacing: 6) {
                            Text("No projects found").font(.clipz(15, .bold)).foregroundStyle(Theme.textWhite)
                            Text("Upload a video above or tap Refresh to load your projects from the server.")
                                .font(.clipz(12.5)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
                        }
                        .padding(24).frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(vm.projects) { proj in
                        Button { vm.openProjectInStudio(proj) } label: { projectRow(proj) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 18)
        }
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

    private var uploadCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.coral.opacity(0.15))
                Circle().stroke(Theme.coral.opacity(0.4), lineWidth: 1)
                VectorIcon(kind: .upload, size: 24, color: Theme.coral)
            }
            .frame(width: 54, height: 54)

            VStack(spacing: 4) {
                Text("Upload a New Reel").font(.clipz(20, .heavy)).foregroundStyle(Theme.textWhite)
                Text("Upload a raw video (max 90s) to the ClipZ server for transcript, beat analysis, and AI editing.")
                    .font(.clipz(13)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            }

            StyledCapsuleInput(
                text: Binding(get: { vm.newReelName }, set: { if $0.count <= 120 { vm.newReelName = $0 } }),
                placeholder: "New reel name (optional)", accent: Theme.coral, singleLine: true)

            Button { showSourceChoice = true } label: {
                HStack(spacing: 8) {
                    VectorIcon(kind: .upload, size: 18, color: Theme.ink)
                    Text(vm.uploadProgress != nil
                         ? (vm.uploadStatusText.isEmpty ? "Uploading…" : vm.uploadStatusText)
                         : "Select Video & Upload")
                        .font(.clipz(14.5, .heavy)).foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(vm.busy ? Theme.disabledGradient : Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(vm.busy)
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
                ProgressView(value: p).tint(Theme.coral)
                    .scaleEffect(x: 1, y: 1.5)
                    .background(Theme.border, in: Capsule())
            }
        }
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.coral.opacity(0.55), lineWidth: 1.5))
    }

    private func projectRow(_ proj: Project) -> some View {
        Card(radius: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.surface2)
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.border)
                    VectorIcon(kind: .play, size: 16, color: Theme.coral)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(proj.name).font(.clipz(15, .bold)).foregroundStyle(Theme.textWhite).lineLimit(1)
                    HStack(spacing: 8) {
                        StatusPill(status: proj.status)
                        Text(formatTimestamp(proj.createdAt)).font(.clipz(11)).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Open →").font(.clipz(12, .bold)).foregroundStyle(Theme.coral)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.coral.opacity(0.4)))
            }
            .padding(14)
        }
    }
}

struct StepPill: View {
    let num: String
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(num).font(.clipz(10, .heavy)).foregroundStyle(active ? .black : Theme.textMuted)
                .frame(width: 18, height: 18)
                .background(active ? Theme.coral : Theme.surface3, in: Circle())
            Text(label).font(.clipz(11, .semibold)).foregroundStyle(active ? Theme.textWhite : Theme.textMuted).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(active ? Theme.coral.opacity(0.14) : Theme.surface1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Theme.coral.opacity(0.5) : Theme.border))
    }
}

// MARK: - Modals

struct DialogOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onDismiss)
            ScrollView {
                content()
                    .padding(24)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Workspace & API Server").font(.clipz(17, .bold)).foregroundStyle(Theme.textWhite)
                Text("Connected to your live ClipZ server. Keep 'reelforge-dev-key' to see your existing projects, or type any new name for a fresh workspace.")
                    .font(.clipz(12)).foregroundStyle(Theme.textMuted)
                StyledCapsuleInput(text: $newKey, placeholder: "Workspace Key", accent: Theme.coral, singleLine: true)
                StyledCapsuleInput(text: $newUrl, placeholder: "API Base URL", accent: Theme.coral, singleLine: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        suggestion("ngrok Live Server") { newUrl = ClipzConfig.baseURL }
                        suggestion("reelforge-dev-key") { newKey = ClipzConfig.workspaceKey }
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Cancel").font(.clipz(14, .medium)).foregroundStyle(Theme.textMuted).padding(.horizontal, 12).padding(.vertical, 9)
                    }.buttonStyle(.plain)
                    Button { onSave(newKey, newUrl) } label: {
                        Text("Save & Connect").font(.clipz(14, .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Theme.coral, in: Capsule())
                    }.buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
    }

    private func suggestion(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.clipz(11)).foregroundStyle(Theme.textWhite)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
        }.buttonStyle(.plain)
    }
}

struct QuickHowToModal: View {
    let onDismiss: () -> Void

    var body: some View {
        DialogOverlay(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to Use ClipZ Studio (3 Easy Steps)").font(.clipz(16, .bold)).foregroundStyle(Theme.textWhite)
                HowToStep(num: "Step 1", title: "Open a Project or Upload a Video",
                          text: "Tap an existing project (like 'Test') or tap 'Select Video & Upload' to send a new video to your ClipZ server.")
                HowToStep(num: "Step 2", title: "Brainstorm, '✦ My style', or Edit",
                          text: "• ✻ Brainstorm: Discuss the edit first without modifying the timeline.\n• ✦ My style: Drafts a prompt learned from how you edited your other reels.\n• ● Edit: Streams real-time Director tool calls and renders a video preview on the server.")
                HowToStep(num: "Step 3", title: "Subtitles, Timeline & Save MP4",
                          text: "• Subtitles: Tap any word (w1, w64, w138…) to insert its ID into your prompt.\n• Timeline: Undo, Redo, or Export final video.\n• Save MP4: Saves the rendered MP4 to your Photos library.")
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Got It").font(.clipz(14, .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .background(Theme.coral, in: Capsule())
                    }.buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("\(num) — \(title)").font(.clipz(12.5, .bold)).foregroundStyle(Theme.coral)
            Text(text).font(.clipz(12)).foregroundStyle(Theme.textWhite).lineSpacing(3)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}
