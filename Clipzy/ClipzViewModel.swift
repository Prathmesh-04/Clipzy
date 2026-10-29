import Foundation
import Observation
import CryptoKit
import Photos

@MainActor
@Observable
final class ClipzViewModel {
    private let defaults = UserDefaults.standard
    private let prefix = "clipz_studio_v3."

    var key: String
    var baseUrl: String
    var serverHealthy: Bool?

    var projects: [Project] = []
    var selected: Project?

    var inStudio = false
    var studioTab = "director" // "director", "transcript", "timeline"
    var videoExpanded = true
    var videoSourceMode = "render" // "render" or "original"

    var feed: [FeedItem] = []
    var renders: [Render] = []
    var sourceVideo: SourceVideo?
    var timelineVersion = 1
    var summary = "No timeline yet."
    var words: [Word] = []

    var mode = "brainstorm"
    var composerInput = ""
    var newReelName = ""

    var busy = false
    var styleLoading = false
    var uploadProgress: Double?
    var uploadStatusText = ""
    var renderProgress: Double?
    var error: String? { didSet { if error != nil { Haptics.error() } } }
    var bannerNotice: String?

    var playingRenderUrl: String?
    var localRenderFile: URL?
    var localOriginalFile: URL?
    var videoLoading = false
    var videoError: String?

    @ObservationIgnored private var players: [String: LoopingPlayer] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init() {
        let k = defaults.string(forKey: prefix + "key") ?? ""
        key = k.isEmpty ? ClipzConfig.workspaceKey : k
        let saved = defaults.string(forKey: prefix + "baseUrl") ?? ""
        let usable = (!saved.isEmpty && !saved.contains("10.0.2.2") && !saved.contains("localhost")) ? saved : ClipzConfig.baseURL
        baseUrl = ClipzApi.normalizeBaseUrl(usable)
    }

    /// One player per video file, so pause/position survive the stage being hidden and re-shown.
    func loopingPlayer(for url: URL) -> LoopingPlayer {
        if let p = players[url.path] { return p }
        let p = LoopingPlayer(url: url)
        players[url.path] = p
        return p
    }

    private func api() -> ClipzApi { ClipzApi(baseUrl: baseUrl, key: key) }

    func saveSettings(key newKey: String, baseUrl newUrl: String) {
        let k = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        key = k.isEmpty ? ClipzConfig.workspaceKey : k
        let u = ClipzApi.normalizeBaseUrl(newUrl)
        baseUrl = u.isEmpty ? ClipzConfig.baseURL : u
        defaults.set(key, forKey: prefix + "key")
        defaults.set(baseUrl, forKey: prefix + "baseUrl")
        loadProjects()
    }

    func clearError() { error = nil }

    func showNotice(_ msg: String) {
        bannerNotice = msg
        Haptics.success()
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.bannerNotice = nil }
        }
    }

    func clearNotice() { bannerNotice = nil }

    private func appendFeed(_ item: FeedItem) { feed.append(item) }

    private func appendSys(_ text: String, isError: Bool = false) {
        appendFeed(.message(id: FeedItem.newId(), role: "sys", text: text, isError: isError))
    }

    // MARK: Brainstorm history (persisted per project)

    private func brainstormHistory(_ pid: String) -> [ChatMessage] {
        guard let raw = defaults.string(forKey: prefix + "rf_brain_\(pid)"),
              let arr = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [JSON] else { return [] }
        return arr.map { ChatMessage(role: $0.optString("role"), text: $0.optString("content")) }
    }

    private func saveBrainstormHistory(_ pid: String, _ list: [ChatMessage]) {
        let arr: [JSON] = list.suffix(30).map { ["role": $0.role, "content": $0.text] }
        defaults.set(jsonString(arr), forKey: prefix + "rf_brain_\(pid)")
    }

    // MARK: Projects

    func loadProjects() {
        Task {
            do {
                serverHealthy = await api().healthCheck()
                let list = try await api().projects()
                projects = list
                serverHealthy = true
                if let sel = selected, let updated = list.first(where: { $0.id == sel.id }) { selected = updated }
            } catch {
                serverHealthy = false
                self.error = "Cannot reach ClipZ server at \(baseUrl) (\(error.localizedDescription))"
            }
        }
    }

    func openProjectInStudio(_ project: Project) {
        pollTask?.cancel()
        players.values.forEach { $0.player.pause() }
        players.removeAll()
        selected = project
        inStudio = true
        studioTab = "director"
        videoExpanded = true
        defaults.set(project.id, forKey: prefix + "rf_last_project")

        feed = []
        renders = []
        sourceVideo = nil
        words = []
        summary = "Loading timeline…"
        renderProgress = nil
        playingRenderUrl = nil
        localRenderFile = nil
        localOriginalFile = nil
        videoError = nil

        let marker = "\n\nFINAL PROMPT: "
        var restored: [FeedItem] = []
        for m in brainstormHistory(project.id) {
            if m.role != "user", let r = m.text.range(of: marker) {
                let replyPart = String(m.text[..<r.lowerBound])
                let promptPart = String(m.text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                restored.append(.message(id: FeedItem.newId(), role: "brain", text: replyPart))
                if !promptPart.isEmpty { restored.append(.finalPrompt(id: FeedItem.newId(), prompt: promptPart)) }
            } else {
                restored.append(.message(id: FeedItem.newId(), role: m.role == "user" ? "user" : "brain", text: m.text))
            }
        }
        feed = restored

        if project.status != "ready" {
            let msg = project.status == "processing"
                ? "Analysing the video (transcript, scenes, beats)… This view updates automatically when ready."
                : "Project status: \(project.status)"
            appendSys(msg, isError: project.status == "failed")
            if project.status == "processing" { startPollingReady(project.id) }
        }

        Task {
            if project.status == "ready" {
                if let serverMessages = try? await api().messages(project.id), selected?.id == project.id {
                    feed += serverMessages.map {
                        .message(id: FeedItem.newId(), role: $0.role == "user" ? "user" : "assistant",
                                 text: $0.text, toolBadges: $0.toolNames)
                    }
                }
            }
            refreshRenders(project.id, autoPlayLatest: true)
            refreshTimeline(project.id)
        }
    }

    private func startPollingReady(_ pid: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for _ in 0..<400 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if self.selected?.id != pid { return }
                do {
                    let list = try await self.api().projects()
                    self.projects = list
                    guard let p = list.first(where: { $0.id == pid }) else { return }
                    if p.status != "processing" {
                        self.selected = p
                        let ok = p.status == "ready"
                        self.appendSys(ok ? "Video analysed. Brainstorm or tell the Director what to do." : "Processing failed.", isError: !ok)
                        if ok {
                            self.refreshTimeline(pid)
                            self.refreshRenders(pid, autoPlayLatest: true)
                        }
                        return
                    }
                } catch {}
            }
        }
    }

    func refreshRenders(_ pidArg: String? = nil, autoPlayLatest: Bool = false) {
        let pid = pidArg ?? selected?.id ?? ""
        if pid.isEmpty { return }
        Task {
            do {
                let list = try await api().renders(pid)
                guard selected?.id == pid else { return }
                renders = list
                if let latest = list.first(where: { $0.status == "done" && !($0.url ?? "").isEmpty }),
                   let url = latest.url, autoPlayLatest || localRenderFile == nil {
                    videoSourceMode = "render"
                    playRenderVideo(url)
                    if !latest.credits.isEmpty && !feed.contains(where: { if case .credits = $0 { true } else { false } }) {
                        appendFeed(.credits(id: FeedItem.newId(), credits: latest.credits))
                    }
                } else if list.isEmpty {
                    videoSourceMode = "original"
                    loadOriginalVideo(pid)
                }
            } catch {}
        }
    }

    func refreshTimeline(_ pidArg: String? = nil) {
        let pid = pidArg ?? selected?.id ?? ""
        guard let proj = selected, proj.id == pid, proj.status == "ready" else { return }
        Task {
            do {
                let info = try await api().timeline(pid)
                guard selected?.id == pid else { return }
                timelineVersion = info.version
                summary = "version \(info.version)\n\n\(info.summary)"
                words = info.words
            } catch {
                if selected?.id == pid { summary = "No timeline yet." }
            }
        }
    }

    // MARK: Video

    func loadOriginalVideo(_ pidArg: String? = nil) {
        let pid = pidArg ?? selected?.id ?? ""
        if pid.isEmpty { return }
        Task {
            if let f = localOriginalFile, FileManager.default.fileExists(atPath: f.path) { return }
            videoLoading = true
            videoError = nil
            defer { videoLoading = false }
            do {
                let src = try await api().source(pid)
                guard selected?.id == pid else { return }
                sourceVideo = src
                if !src.url.isEmpty {
                    let file = try await downloadCachedVideo(src.url)
                    if selected?.id == pid { localOriginalFile = file }
                }
            } catch {
                if selected?.id == pid { videoError = "Original video unavailable: \(error.localizedDescription)" }
            }
        }
    }

    func playRenderVideo(_ url: String) {
        guard let proj = selected else { return }
        playingRenderUrl = url
        videoSourceMode = "render"
        Task {
            videoLoading = true
            videoError = nil
            defer { videoLoading = false }
            do {
                let file = try await downloadCachedVideo(url)
                if selected?.id == proj.id && playingRenderUrl == url { localRenderFile = file }
            } catch {
                if selected?.id == proj.id { videoError = "Cannot load video: \(error.localizedDescription)" }
            }
        }
    }

    private func downloadCachedVideo(_ url: String) async throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("clipz_videos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hash = Insecure.MD5.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return try await api().downloadVideo(urlPath: url, to: folder.appendingPathComponent("vid_\(hash).mp4"))
    }

    /// The video currently shown in the stage (rendered result, else original).
    var currentVideoFile: URL? {
        let f = (videoSourceMode == "render" && localRenderFile != nil) ? localRenderFile : (localOriginalFile ?? localRenderFile)
        guard let f, FileManager.default.fileExists(atPath: f.path) else { return nil }
        return f
    }

    var saveFileName: String {
        let name = selected?.name ?? ""
        let clean = name.replacingOccurrences(of: "[^\\w-]+", with: "_", options: .regularExpression)
        return "\(clean.isEmpty ? "clipz_reel" : clean)_v\(timelineVersion)_\(Int(Date().timeIntervalSince1970)).mp4"
    }

    /// Saves the MP4 to the Photos library (needs add-only Photos permission).
    func saveCurrentVideoToPhotos() {
        guard let file = currentVideoFile else {
            showNotice("Wait for the video to finish loading first")
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                error = "Photos access is off. Enable it in Settings > ClipZ Studio > Photos."
                return
            }
            // Photos needs a file with a proper video extension; copy from the cache so the original stays intact.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(saveFileName)
            do {
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: file, to: tmp)
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let opts = PHAssetResourceCreationOptions()
                    opts.shouldMoveFile = true
                    req.addResource(with: .video, fileURL: tmp, options: opts)
                }
                showNotice("Saved to Photos: \(tmp.lastPathComponent)")
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                self.error = "Could not save video to Photos: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Upload

    func uploadVideo(fileURL: URL, fileName: String) {
        Task {
            busy = true
            error = nil
            uploadProgress = 0.05
            uploadStatusText = "Creating project on server…"
            defer { busy = false; try? FileManager.default.removeItem(at: fileURL) }
            do {
                let stem = (fileName as NSString).deletingPathExtension
                let custom = newReelName.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = custom.isEmpty ? (stem.isEmpty ? "New Reel" : String(stem.prefix(80))) : custom
                let project = try await api().createProject(title)
                uploadStatusText = "Uploading video…"
                let jobId = try await api().upload(fileURL: fileURL, name: fileName, project: project) { [weak self] p in
                    Task { @MainActor in
                        self?.uploadProgress = p
                        self?.uploadStatusText = "Uploading \(Int(p * 100))%"
                    }
                }
                if !jobId.isEmpty {
                    uploadStatusText = "Ingesting video…"
                    do {
                        try await api().streamSse(path: "/projects/\(project.id)/jobs/\(jobId)/events") { [weak self] _, raw in
                            guard let self, let d = parseJSON(raw) else { return }
                            let err = d.optString("error")
                            self.uploadProgress = min(max(d.optDouble("progress"), 0), 1)
                            self.uploadStatusText = "Ingest \(d.optString("status", "ingesting"))" + (err.isEmpty ? "" : ": \(err)")
                        }
                    } catch {}
                }
                newReelName = ""
                uploadProgress = nil
                uploadStatusText = "Uploaded. Analysing…"
                let updated = try await api().projects()
                projects = updated
                openProjectInStudio(updated.first(where: { $0.id == project.id }) ?? project)
                uploadStatusText = ""
            } catch {
                uploadProgress = nil
                uploadStatusText = ""
                self.error = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Director

    func sendText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, selected != nil, !busy else { return }
        composerInput = ""
        if mode == "brainstorm" { runBrainstorm(text) } else { runEdit(text) }
    }

    func runBrainstorm(_ text: String) {
        guard let proj = selected else { return }
        let pid = proj.id
        studioTab = "director"
        Task {
            busy = true
            error = nil
            defer { busy = false }
            var hist = brainstormHistory(pid)
            hist.append(ChatMessage(role: "user", text: text))
            appendFeed(.message(id: FeedItem.newId(), role: "user", text: text))
            let thinkingId = FeedItem.newId()
            appendFeed(.message(id: thinkingId, role: "sys", text: "✻ Brainstorming with ClipZ Director…"))
            do {
                let res = try await api().brainstorm(pid, history: hist)
                feed.removeAll { $0.id == thinkingId }
                let stored = res.reply + ((res.finalPrompt ?? "").isEmpty ? "" : "\n\nFINAL PROMPT: \(res.finalPrompt!)")
                hist.append(ChatMessage(role: "assistant", text: stored))
                saveBrainstormHistory(pid, hist)
                if selected?.id == pid {
                    appendFeed(.message(id: FeedItem.newId(), role: "brain", text: res.reply))
                    if let fp = res.finalPrompt, !fp.isEmpty {
                        appendFeed(.finalPrompt(id: FeedItem.newId(), prompt: fp))
                    }
                }
            } catch {
                feed.removeAll { $0.id == thinkingId }
                appendSys("Brainstorm failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func requestMyStyle() {
        guard let proj = selected, !busy, !styleLoading else { return }
        let pid = proj.id
        studioTab = "director"
        Task {
            styleLoading = true
            error = nil
            defer { styleLoading = false }
            let waitId = FeedItem.newId()
            appendFeed(.message(id: waitId, role: "sys", text: "✦ Learning your style from your other reels…"))
            do {
                let res = try await api().stylePrompt(pid)
                feed.removeAll { $0.id == waitId }
                if selected?.id == pid {
                    appendFeed(.style(id: FeedItem.newId(), note: res.note, prompt: res.prompt, habits: res.habits))
                }
            } catch {
                feed.removeAll { $0.id == waitId }
                appendSys("Could not learn your style: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func discardCard(_ id: String) { feed.removeAll { $0.id == id } }

    func submitStylePrompt(cardId: String, editedPrompt: String) {
        let clean = editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !busy else { return }
        feed = feed.map {
            if case .style(let id, let note, _, let habits, _) = $0, id == cardId {
                return .style(id: id, note: note, prompt: clean, habits: habits, submitted: true)
            }
            return $0
        }
        mode = "edit"
        runEdit(clean)
    }

    func runEdit(_ text: String) {
        guard let proj = selected else { return }
        if proj.status != "ready" {
            showNotice("Wait for video analysis to finish ('ready') before running edits.")
            return
        }
        let pid = proj.id
        mode = "edit"
        studioTab = "director"
        Task {
            busy = true
            error = nil
            appendFeed(.message(id: FeedItem.newId(), role: "user", text: text))
            do {
                try await api().streamSse(path: "/projects/\(pid)/messages", method: "POST",
                                          body: jsonString(["text": text])) { [weak self] ev, raw in
                    guard let self, self.selected?.id == pid else { return }
                    self.handleEditEvent(ev, raw, pid: pid)
                }
            } catch {
                appendSys("Request failed: \(error.localizedDescription)", isError: true)
            }
            busy = false
            if selected?.id == pid {
                refreshTimeline(pid)
                refreshRenders(pid)
            }
        }
    }

    private func handleEditEvent(_ ev: String, _ raw: String, pid: String) {
        let d = parseJSON(raw) ?? [:]
        switch ev {
        case "tool_call":
            let toolId = d["id"] != nil ? d.optString("id") : FeedItem.newId()
            let name = d.optString("name", "tool")
            let args = d.optObject("args")
            if name == "plan_edit", let plan = ClipzApi.parsePlanEdit(args) {
                appendFeed(.plan(id: FeedItem.newId(), plan: plan))
            }
            appendFeed(.toolStep(id: FeedItem.newId(), toolCallId: toolId, name: name,
                                 argsText: ClipzApi.formatToolArgs(args), status: "run"))
        case "tool_result":
            let toolId = d.optString("id")
            let ok = d.optBool("ok", true)
            let res = ok ? ClipzApi.formatToolResult(d.optObject("result")) : d.optString("error", "Tool failed")
            feed = feed.map {
                if case .toolStep(let id, let tcid, let name, let args, _, _) = $0, tcid == toolId {
                    return .toolStep(id: id, toolCallId: tcid, name: name, argsText: args, status: ok ? "ok" : "fail", resultText: res)
                }
                return $0
            }
        case "timeline_version_created":
            refreshTimeline(pid)
        case "preview_queued", "render_queued":
            renderProgress = 0.04
            refreshRenders(pid)
        case "render_progress":
            renderProgress = min(max(d.optDouble("progress"), 0), 1)
        case "preview_ready", "render_ready":
            renderProgress = nil
            let url = d.optString("url")
            refreshRenders(pid)
            if !url.isEmpty { playRenderVideo(url) }
            if let c = d.optArray("credits"), !c.isEmpty {
                appendFeed(.credits(id: FeedItem.newId(), credits: c.map { "\($0)" }))
            }
            showNotice("Render complete! Playing above.")
        case "render_failed":
            renderProgress = nil
            appendSys("Render failed.", isError: true)
            refreshRenders(pid)
        case "dub_queued":
            appendSys("Dubbing into \(d.optString("language", "target language")) in the background; it will appear as a new version.")
        case "critic_feedback":
            let score = d["overall_score"].map { "\($0)" } ?? "?"
            appendFeed(.critic(id: FeedItem.newId(), score: score, issues: (d.optArray("issues") ?? []).map { "\($0)" }))
        case "ask":
            appendFeed(.ask(id: FeedItem.newId(), question: d.optString("question"),
                            options: (d.optArray("options") ?? []).map { "\($0)" }))
        case "done":
            let reply = d.optString("reply")
            if !reply.isEmpty { appendFeed(.message(id: FeedItem.newId(), role: "assistant", text: reply)) }
        case "error":
            let msg = d.optString("message")
            appendSys("Error: \(msg.isEmpty ? raw : msg)", isError: true)
        default:
            break
        }
    }

    func answerAskCard(_ cardId: String, option: String) {
        guard !busy else { return }
        feed = feed.map {
            if case .ask(let id, let q, let opts, _) = $0, id == cardId {
                return .ask(id: id, question: q, options: opts, selectedOption: option)
            }
            return $0
        }
        runEdit(option)
    }

    func insertWordId(_ wordId: String, text: String) {
        let prefix = (!composerInput.isEmpty && !composerInput.hasSuffix(" ")) ? " " : ""
        composerInput += "\(prefix)\(wordId) "
        studioTab = "director"
        showNotice("Added \(wordId) (\"\(text)\") to prompt")
    }

    func performUndo() {
        guard let proj = selected else { return }
        Task {
            do {
                try await api().undo(proj.id)
                refreshTimeline(proj.id)
                showNotice("Undid timeline change")
            } catch { self.error = "Undo failed: \(error.localizedDescription)" }
        }
    }

    func performRedo() {
        guard let proj = selected else { return }
        Task {
            do {
                try await api().redo(proj.id)
                refreshTimeline(proj.id)
                showNotice("Redid timeline change")
            } catch { self.error = "Redo failed: \(error.localizedDescription)" }
        }
    }
}
