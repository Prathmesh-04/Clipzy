import SwiftUI

// MARK: - Premium studio color system (same hex values as the Android app)

extension Color {
    init(hex: UInt32) {
        let a = Double((hex >> 24) & 0xFF) / 255
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: a == 0 ? 1 : a)
    }
}

enum Theme {
    static let bgDeep = Color(hex: 0xFF08090D)
    static let surface1 = Color(hex: 0xFF11131B)
    static let surface2 = Color(hex: 0xFF181C28)
    static let surface3 = Color(hex: 0xFF222738)
    static let border = Color(hex: 0xFF282E42)
    static let textWhite = Color(hex: 0xFFF5F7FF)
    static let textMuted = Color(hex: 0xFF8E96AA)
    static let coral = Color(hex: 0xFFFF7A59)
    static let amber = Color(hex: 0xFFE05A47)
    static let blue = Color(hex: 0xFF58A6FF)
    static let violet = Color(hex: 0xFFA78BFA)
    static let green = Color(hex: 0xFF34D399)
    static let yellow = Color(hex: 0xFFFBBF24)
    static let red = Color(hex: 0xFFF87171)
    static let ink = Color(hex: 0xFF090A0F)

    static let accentGradient = LinearGradient(colors: [coral, amber], startPoint: .leading, endPoint: .trailing)
    static let brainstormGradient = LinearGradient(colors: [blue, Color(hex: 0xFF3B82F6)], startPoint: .leading, endPoint: .trailing)
    static let styleGradient = LinearGradient(colors: [Color(hex: 0xFF8B5CF6), Color(hex: 0xFF6366F1)], startPoint: .leading, endPoint: .trailing)
    static let heroGradient = LinearGradient(colors: [Color(hex: 0xFF191D2B), Color(hex: 0xFF11131B)], startPoint: .top, endPoint: .bottom)
    static let disabledGradient = LinearGradient(colors: [surface3, surface3], startPoint: .leading, endPoint: .trailing)

    static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "ready", "done": return green
        case "failed", "error": return red
        case "processing", "queued": return yellow
        default: return textMuted
        }
    }
}

func formatTimestamp(_ raw: String) -> String {
    if raw.isEmpty { return "" }
    let s = raw.replacingOccurrences(of: "T", with: " ")
    return s.components(separatedBy: ".").first ?? s
}

// MARK: - Text helper

extension Font {
    static func clipz(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        .system(size: size, weight: weight, design: mono ? .monospaced : .default)
    }
}

// MARK: - Card / chip containers

struct Card<Content: View>: View {
    var fill: Color = Theme.surface1
    var radius: CGFloat = 14
    var stroke: Color = Theme.border
    var lineWidth: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: lineWidth))
    }
}

struct StatusPill: View {
    let status: String
    var body: some View {
        let c = Theme.statusColor(status)
        Text(status.uppercased())
            .font(.clipz(9.5, .heavy))
            .foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(c.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(c.opacity(0.45), lineWidth: 1))
    }
}

struct FilledButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.clipz(12, .heavy)).foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.coral.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct OutlinedBtn: View {
    let title: String
    var color: Color = Theme.textWhite
    var stroke: Color = Theme.border
    var size: CGFloat = 12
    var weight: Font.Weight = .regular
    var enabled = true
    var radius: CGFloat = 10
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.clipz(size, weight)).foregroundStyle(color.opacity(enabled ? 1 : 0.4))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - Capsule text input

struct StyledCapsuleInput: View {
    @Binding var text: String
    let placeholder: String
    let accent: Color
    var singleLine = false
    var maxLines = 4
    var onSend: (() -> Void)?
    var focus: FocusState<Bool>.Binding?

    @FocusState private var localFocus: Bool

    var body: some View {
        let field = TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.textMuted).font(.clipz(13.5)),
                              axis: singleLine ? .horizontal : .vertical)
            .lineLimit(singleLine ? 1...1 : 1...maxLines)
            .font(.clipz(14))
            .foregroundStyle(Theme.textWhite)
            .tint(accent)
            .textInputAutocapitalization(singleLine && placeholder.contains("URL") ? .never : .sentences)
            .autocorrectionDisabled(placeholder.contains("URL") || placeholder.contains("Key"))
            .submitLabel(onSend != nil ? .send : .done)
            .onSubmit { onSend?() }

        Group {
            if let focus { field.focused(focus) } else { field.focused($localFocus) }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke((focus?.wrappedValue ?? localFocus) ? accent : Theme.border,
                        lineWidth: (focus?.wrappedValue ?? localFocus) ? 1.5 : 1)
        )
    }
}

// MARK: - Custom vector icons (ported from the Canvas drawings)

enum IconKind { case play, upload, download, send, back, gear }

struct VectorIcon: View {
    let kind: IconKind
    let size: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func stroke(_ p: Path, _ lw: CGFloat) {
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w * lw, lineCap: .round, lineJoin: .round))
            }
            switch kind {
            case .play:
                var p = Path(); p.move(to: pt(0.22, 0.15)); p.addLine(to: pt(0.85, 0.5)); p.addLine(to: pt(0.22, 0.85)); p.closeSubpath()
                ctx.fill(p, with: .color(color))
            case .upload:
                var line = Path(); line.move(to: pt(0.5, 0.72)); line.addLine(to: pt(0.5, 0.2)); stroke(line, 0.11)
                var head = Path(); head.move(to: pt(0.26, 0.42)); head.addLine(to: pt(0.5, 0.18)); head.addLine(to: pt(0.74, 0.42)); stroke(head, 0.11)
                var tray = Path(); tray.move(to: pt(0.18, 0.65)); tray.addLine(to: pt(0.18, 0.84)); tray.addLine(to: pt(0.82, 0.84)); tray.addLine(to: pt(0.82, 0.65)); stroke(tray, 0.11)
            case .download:
                var line = Path(); line.move(to: pt(0.5, 0.18)); line.addLine(to: pt(0.5, 0.68)); stroke(line, 0.12)
                var head = Path(); head.move(to: pt(0.26, 0.48)); head.addLine(to: pt(0.5, 0.72)); head.addLine(to: pt(0.74, 0.48)); stroke(head, 0.12)
                var base = Path(); base.move(to: pt(0.2, 0.86)); base.addLine(to: pt(0.8, 0.86)); stroke(base, 0.12)
            case .send:
                var p = Path()
                p.move(to: pt(0.15, 0.5)); p.addLine(to: pt(0.85, 0.5))
                p.move(to: pt(0.55, 0.22)); p.addLine(to: pt(0.85, 0.5)); p.addLine(to: pt(0.55, 0.78))
                stroke(p, 0.12)
            case .back:
                var p = Path(); p.move(to: pt(0.68, 0.2)); p.addLine(to: pt(0.32, 0.5)); p.addLine(to: pt(0.68, 0.8)); stroke(p, 0.13)
            case .gear:
                let r = w * 0.28
                ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2)),
                           with: .color(color), lineWidth: w * 0.13)
                let d = w * 0.08
                ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - d, y: h / 2 - d, width: d * 2, height: d * 2)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
