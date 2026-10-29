import Foundation

typealias JSON = [String: Any]

// MARK: - Config (reads the bundled copy of the Android `.env`)

enum ClipzConfig {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "clipz", withExtension: "env"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            }
            out[k] = v
        }
        return out
    }()

    static let baseURL = values["CLIPZ_BASE_URL"] ?? "http://localhost:8000"
    static let workspaceKey = values["CLIPZ_WORKSPACE_KEY"] ?? "reelforge-dev-key"
}

// MARK: - JSON helpers (mirror org.json optString/optInt semantics)

extension Dictionary where Key == String, Value == Any {
    func optString(_ k: String, _ def: String = "") -> String {
        guard let v = self[k], !(v is NSNull) else { return def }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return def
    }
    func optDouble(_ k: String, _ def: Double = 0) -> Double {
        (self[k] as? NSNumber)?.doubleValue ?? Double(optString(k)) ?? def
    }
    func optInt(_ k: String, _ def: Int = 0) -> Int {
        (self[k] as? NSNumber)?.intValue ?? def
    }
    func optBool(_ k: String, _ def: Bool = false) -> Bool {
        (self[k] as? NSNumber)?.boolValue ?? def
    }
    func nonNull(_ k: String) -> Any? {
        guard let v = self[k], !(v is NSNull) else { return nil }
        return v
    }
    func optArray(_ k: String) -> [Any]? { self[k] as? [Any] }
    func optObject(_ k: String) -> JSON? { self[k] as? JSON }
}

func parseJSON(_ text: String) -> JSON? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? JSON
}

func jsonString(_ obj: Any) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: d, encoding: .utf8) else { return "{}" }
    return s
}

struct ApiError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - API

final class ClipzApi {
    let baseUrl: String
    let key: String

    init(baseUrl: String, key: String) {
        self.baseUrl = baseUrl
        self.key = key
    }

    static func normalizeBaseUrl(_ raw: String) -> String {
        func trimSlash(_ s: String) -> String {
            var s = s
            while s.hasSuffix("/") { s.removeLast() }
            return s
        }
        var u = trimSlash(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if u.hasSuffix("/healthz") { u = trimSlash(String(u.dropLast("/healthz".count))) }
        if u.hasSuffix("/app") { u = trimSlash(String(u.dropLast("/app".count))) }
        return u
    }

    private func resolveUrl(_ path: String) throws -> URL {
        let s: String
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            s = path
        } else {
            s = Self.normalizeBaseUrl(baseUrl) + (path.hasPrefix("/") ? path : "/" + path)
        }
        guard let url = URL(string: s) else { throw ApiError(message: "Invalid URL: \(s)") }
        return url
    }

    private func parseError(_ code: Int, _ raw: String) -> String {
        var detail = raw
        if let json = parseJSON(raw) {
            if json["detail"] != nil {
                detail = json.optString("detail")
            } else if let errs = json.optArray("errors") {
                detail = ((errs.first as? JSON)?.optString("message")).flatMap { $0.isEmpty ? nil : $0 } ?? raw
            }
        }
        return detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HTTP \(code)" : String(detail.prefix(240))
    }

    private func makeRequest(_ path: String, method: String, body: String?, timeout: TimeInterval, accept: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: try resolveUrl(path), timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
        }
        return req
    }

    private func request(_ path: String, method: String = "GET", body: String? = nil) async throws -> String {
        let req = try makeRequest(path, method: method, body: body, timeout: 120)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard (200...299).contains(code) else { throw ApiError(message: parseError(code, text)) }
        return text
    }

    private func requestJSON(_ path: String, method: String = "GET", body: String? = nil) async throws -> JSON {
        parseJSON(try await request(path, method: method, body: body)) ?? [:]
    }

    func healthCheck() async -> Bool {
        do { return try await requestJSON("/healthz").optString("status") == "ok" } catch { return false }
    }

    func projects() async throws -> [Project] {
        let arr = try await requestJSON("/projects").optArray("projects") ?? []
        return arr.compactMap { ($0 as? JSON).map(projectFrom) }
    }

    func createProject(_ name: String) async throws -> Project {
        projectFrom(try await requestJSON("/projects", method: "POST", body: jsonString(["name": name])))
    }

    func messages(_ id: String) async throws -> [ChatMessage] {
        let arr = try await requestJSON("/projects/\(id)/messages").optArray("messages") ?? []
        return arr.compactMap { $0 as? JSON }.map { item in
            let tools = (item.optArray("tool_calls") ?? []).compactMap { ($0 as? JSON)?.optString("name") }.filter { !$0.isEmpty }
            return ChatMessage(role: item.optString("role"), text: item.optString("content"), toolNames: tools)
        }
    }

    func brainstorm(_ id: String, history: [ChatMessage]) async throws -> BrainstormResult {
        let messages: [JSON] = history.suffix(20).map {
            ["role": $0.role == "user" ? "user" : "assistant", "content": $0.text]
        }
        let result = try await requestJSON("/projects/\(id)/brainstorm", method: "POST", body: jsonString(["messages": messages]))
        let reply = result.optString("reply").isEmpty ? "The Director did not return a reply." : result.optString("reply")
        let fp = result.nonNull("final_prompt") != nil ? result.optString("final_prompt") : ""
        return BrainstormResult(reply: reply, finalPrompt: (fp.isEmpty || fp == "null") ? nil : fp)
    }

    func stylePrompt(_ id: String) async throws -> StylePromptResult {
        let root = try await requestJSON("/projects/\(id)/style-prompt")
        let p = root.nonNull("prompt") != nil ? root.optString("prompt") : ""
        let habits = (root.optArray("habits") ?? []).compactMap { $0 as? JSON }.map {
            StyleHabit(label: $0.optString("label"), share: $0.optDouble("share"), instruction: $0.optString("instruction"))
        }
        return StylePromptResult(prompt: (p.isEmpty || p == "null") ? nil : p,
                                 note: root.optString("note", "Learned from your workspace history."),
                                 habits: habits)
    }

    func renders(_ id: String) async throws -> [Render] {
        let arr = try await requestJSON("/projects/\(id)/renders").optArray("renders") ?? []
        return arr.enumerated().compactMap { (i, any) in
            guard let item = any as? JSON else { return nil }
            let credits = (item.optArray("credits") ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
            let u = item.nonNull("url") != nil ? item.optString("url") : ""
            return Render(id: item.optString("render_id", "\(i)"),
                          profile: item.optString("profile", "preview"),
                          status: item.optString("status", "processing"),
                          createdAt: item.optString("created_at"),
                          url: (u.isEmpty || u == "null") ? nil : u,
                          credits: credits)
        }
    }

    func source(_ id: String) async throws -> SourceVideo {
        let r = try await requestJSON("/projects/\(id)/source")
        return SourceVideo(url: r.optString("url"),
                           width: r.nonNull("width") != nil ? r.optInt("width") : nil,
                           height: r.nonNull("height") != nil ? r.optInt("height") : nil,
                           durationS: r.nonNull("duration_s") != nil ? r.optDouble("duration_s") : nil)
    }

    func timeline(_ id: String) async throws -> TimelineInfo {
        let root = try await requestJSON("/projects/\(id)/timeline")
        let words = ((root.optObject("timeline")?.optObject("transcript")?.optArray("words")) ?? [])
            .compactMap { $0 as? JSON }
            .map { item -> Word in
                let dt = item.optString("display_text")
                return Word(id: item.optString("id"), text: dt.isEmpty ? item.optString("text") : dt, start: item.optDouble("start"))
            }
        return TimelineInfo(version: root.optInt("version", 1),
                            summary: root.optString("summary", "No summary available."),
                            words: words)
    }

    func undo(_ id: String) async throws { _ = try await request("/projects/\(id)/undo", method: "POST", body: "{}") }
    func redo(_ id: String) async throws { _ = try await request("/projects/\(id)/redo", method: "POST", body: "{}") }

    // MARK: Upload (multipart streamed from a staged file so Content-Length is known)

    func upload(fileURL: URL, name: String, project: Project, onProgress: @escaping @Sendable (Double) -> Void) async throws -> String {
        var base = (name as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        base = base.replacingOccurrences(of: "^[^A-Za-z0-9]+", with: "v", options: .regularExpression)
        if base.isEmpty { base = "video" }
        let safeName = base + ".mp4"
        let boundary = "ClipZ-\(Int(Date().timeIntervalSince1970 * 1000))"

        // Build the multipart body on disk to avoid loading the video into memory.
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload_body_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: bodyURL)
        try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: video/mp4\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: fileURL)
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try input.close()
        try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try out.close()

        var req = URLRequest(url: try resolveUrl("/projects/\(project.id)/uploads"), timeoutInterval: 240)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress)
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: bodyURL, delegate: delegate)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard (200...299).contains(code) else { throw ApiError(message: "Upload failed: \(parseError(code, text))") }
        return parseJSON(text)?.optString("job_id") ?? ""
    }

    // MARK: SSE

    func streamSse(path: String, method: String = "GET", body: String? = nil,
                   onEvent: @MainActor (String, String) async -> Void) async throws {
        let req = try makeRequest(path, method: method, body: body, timeout: 300, accept: "text/event-stream")
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            var errData = Data()
            for try await b in bytes { errData.append(b); if errData.count > 4096 { break } }
            throw ApiError(message: parseError(code, String(decoding: errData, as: UTF8.self)))
        }
        // AsyncBytes.lines drops blank lines, which delimit SSE events, so split manually.
        var currentEvent = "message"
        var data = ""
        var hasData = false
        var lineBuf = [UInt8]()

        func handle(_ line: String) async {
            if line.isEmpty {
                if hasData {
                    let payload = data, ev = currentEvent
                    data = ""; hasData = false; currentEvent = "message"
                    await onEvent(ev, payload)
                }
            } else if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                if hasData { data += "\n" }
                data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                hasData = true
            }
        }

        for try await byte in bytes {
            if byte == 0x0A {
                if lineBuf.last == 0x0D { lineBuf.removeLast() }
                await handle(String(decoding: lineBuf, as: UTF8.self))
                lineBuf.removeAll(keepingCapacity: true)
            } else {
                lineBuf.append(byte)
            }
        }
        if !lineBuf.isEmpty { await handle(String(decoding: lineBuf, as: UTF8.self)) }
        if hasData { await onEvent(currentEvent, data) }
    }

    // MARK: Video download

    func downloadVideo(urlPath: String, to target: URL) async throws -> URL {
        if let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size]) as? Int, size > 0 {
            return target
        }
        let req = try makeRequest(urlPath, method: "GET", body: nil, timeout: 180)
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let err = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
            throw ApiError(message: "Failed to load video: \(parseError(code, err))")
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        return target
    }

    private func projectFrom(_ item: JSON) -> Project {
        Project(id: item.optString("project_id"),
                name: item.optString("name", "Untitled Reel"),
                status: item.optString("status", "processing"),
                createdAt: item.optString("created_at"))
    }

    // MARK: Formatting helpers

    static func formatToolArgs(_ args: JSON?) -> String {
        guard let args else { return "" }
        return args.map { k, v in
            let s: String
            if let str = v as? String { s = str }
            else if let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) { s = String(decoding: data, as: UTF8.self) }
            else { s = "\(v)" }
            let brief = s.count > 36 ? String(s.prefix(35)) + "…" : s
            return "\(k)=\(brief)"
        }.joined(separator: ", ")
    }

    static func formatToolResult(_ r: JSON?) -> String {
        guard let r else { return "" }
        if let placed = r.optArray("placed") {
            let placedLines: [String] = placed.map { x in
                if let o = x as? JSON {
                    let w = o.optString("at_word").isEmpty ? o.optString("word") : o.optString("at_word")
                    let said = o.optString("said").isEmpty ? "" : "\"\(o.optString("said"))\" "
                    let title = o.optString("title").isEmpty ? o.optString("kind") : o.optString("title")
                    return "\(w) \(said)→ \(title)".trimmingCharacters(in: .whitespaces)
                }
                return "\(x)"
            }
            let skipped: [String] = (r.optArray("skipped") ?? []).compactMap { x in
                guard let o = x as? JSON else { return nil }
                let w = o.optString("at_word").isEmpty ? o.optString("word") : o.optString("at_word")
                return "skipped \(w): \(o.optString("reason"))"
            }
            let combined = (placedLines + skipped).filter { !$0.isEmpty }.joined(separator: "\n")
            return combined.isEmpty ? "nothing placed" : combined
        }
        if r["render_id"] != nil {
            let p = r.optString("profile")
            return p.isEmpty ? "render queued" : "render queued (\(p))"
        }
        if let w = r.optArray("warnings") {
            return w.isEmpty ? "plan accepted" : w.map { "\($0)" }.joined(separator: "\n")
        }
        if let res = r.optArray("results") {
            return res.compactMap { x -> String? in
                guard let o = x as? JSON else { return nil }
                return "\(o.optString("id")) — \(o.optString("title"))"
            }.joined(separator: "\n")
        }
        if let v = r["version"] { return "version \(v)" }
        let raw = jsonString(r)
        return raw.count > 160 ? String(raw.prefix(159)) + "…" : raw
    }

    static func parsePlanEdit(_ args: JSON?) -> EditPlan? {
        guard let args else { return nil }
        let steps = (args.optArray("steps") ?? []).map { "\($0)" }
        let moments = (args.optArray("moments") ?? []).compactMap { x -> PlanMoment? in
            guard let m = x as? JSON else { return nil }
            return PlanMoment(atWord: m.optString("at_word"), show: m.optString("show"))
        }
        func nn(_ k: String) -> String? { let s = args.optString(k); return (s.isEmpty || s == "null") ? nil : s }
        return EditPlan(summary: args.optString("summary"), steps: steps, moments: moments,
                        musicMood: nn("music_mood"), transition: nn("transition"))
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1))
    }
}
