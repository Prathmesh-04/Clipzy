import SwiftUI
import CoreText
import UIKit

// MARK: - ClipZ brand tokens (taken from the clipz-landing site: cobalt / yellow / ink / paper)

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
    static let cobalt = Color(hex: 0xFF2430FF)
    static let cobaltDeep = Color(hex: 0xFF1A22C9)
    static let ink = Color(hex: 0xFF0B0B14)
    static let ink2 = Color(hex: 0xFF14142A)
    static let ink3 = Color(hex: 0xFF1C1C38)
    static let paper = Color(hex: 0xFFF2F0FF)
    static let white = Color.white
    static let yellow = Color(hex: 0xFFFFD400)
    static let muted = Color(hex: 0xFF8B8FD9)
    static let line = Color(hex: 0xFF2A2A44)
    static let lineLight = Color(hex: 0xFFD8D5F5)
    static let green = Color(hex: 0xFF7CF29A)
    static let red = Color(hex: 0xFFFF6B6B)
    static let periwinkle = Color(hex: 0xFF8B8FD9)

    static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "ready", "done": return green
        case "failed", "error": return red
        case "processing", "queued": return yellow
        default: return muted
        }
    }
}

func formatTimestamp(_ raw: String) -> String {
    if raw.isEmpty { return "" }
    let s = raw.replacingOccurrences(of: "T", with: " ")
    return s.components(separatedBy: ".").first ?? s
}

// MARK: - Fonts (Unbounded display, Hanken Grotesk body, JetBrains Mono labels)

enum AppFonts {
    static func register() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .custom("Unbounded", size: size).weight(weight)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Hanken Grotesk", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Neo-brutalist building blocks (hard offset shadows, 2px ink borders, pill buttons)

extension View {
    /// Solid offset shadow like the site's `5px 5px 0 ink`.
    func hardShadow(_ color: Color = Theme.ink, offset: CGFloat = 4, radius: CGFloat = 16) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color).offset(x: offset, y: offset))
    }
}

struct BrutalButtonStyle: ButtonStyle {
    var fill: Color = Theme.yellow
    var foreground: Color = Theme.ink
    var shadow: Color = Theme.ink
    var stroke: Color? = nil
    var offset: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill))
            .overlay { if let stroke { Capsule().stroke(stroke, lineWidth: 2) } }
            .background(Capsule().fill(shadow).offset(x: pressed ? 1 : offset, y: pressed ? 1 : offset))
            .offset(x: pressed ? offset - 1 : 0, y: pressed ? offset - 1 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
            .contentShape(Capsule())
    }
}

/// Plain pressable (scales slightly) for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct Card<Content: View>: View {
    var fill: Color = Theme.ink2
    var radius: CGFloat = 20
    var stroke: Color = Theme.line
    var lineWidth: CGFloat = 1.5
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: lineWidth))
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text.uppercased()).font(.mono(11, .bold)).tracking(1.6).foregroundStyle(color)
    }
}

struct StatusPill: View {
    let status: String
    var body: some View {
        let c = Theme.statusColor(status)
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(status.uppercased()).font(.mono(10, .bold)).foregroundStyle(c)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(c.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(c.opacity(0.4), lineWidth: 1))
    }
}

/// Yellow primary pill with the site's hard shadow.
struct PrimaryButton: View {
    let title: String
    var icon: IconKind?
    var enabled = true
    var shadow: Color = Theme.ink
    var fullWidth = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { VectorIcon(kind: icon, size: 16, color: Theme.ink) }
                Text(title).font(.display(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 20).frame(height: 46)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(BrutalButtonStyle(fill: Theme.yellow, shadow: enabled ? shadow : .clear))
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    let title: String
    var color: Color = Theme.paper
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title).font(.ui(13.5, .bold)).foregroundStyle(color.opacity(enabled ? 1 : 0.4))
                .padding(.horizontal, 16).frame(height: 42)
                .overlay(Capsule().stroke(color.opacity(enabled ? 0.55 : 0.2), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// MARK: - Text input

struct StyledCapsuleInput: View {
    @Binding var text: String
    let placeholder: String
    var accent: Color = Theme.yellow
    var singleLine = false
    var maxLines = 4
    var light = false
    var onSend: (() -> Void)?
    var focus: FocusState<Bool>.Binding?

    @FocusState private var localFocus: Bool

    var body: some View {
        let isURLOrKey = placeholder.contains("URL") || placeholder.contains("Key")
        let phColor = light ? Theme.ink.opacity(0.4) : Theme.muted
        let field = TextField("", text: $text,
                              prompt: Text(placeholder).foregroundColor(phColor).font(.ui(14.5)),
                              axis: singleLine ? .horizontal : .vertical)
            .lineLimit(singleLine ? 1...1 : 1...maxLines)
            .font(.ui(15.5, .medium))
            .foregroundStyle(light ? Theme.ink : Theme.paper)
            .tint(light ? Theme.cobalt : accent)
            .textInputAutocapitalization(isURLOrKey ? .never : .sentences)
            .autocorrectionDisabled(isURLOrKey)
            .submitLabel(onSend != nil ? .send : .done)
            .onSubmit {
                if let onSend { onSend() } else { localFocus = false; focus?.wrappedValue = false }
            }

        let focused = focus?.wrappedValue ?? localFocus
        Group {
            if let focus { field.focused(focus) } else { field.focused($localFocus) }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(light ? Color.white : Theme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(light ? (focused ? Theme.cobalt : Theme.ink) : (focused ? accent : Theme.line),
                        lineWidth: light ? 2 : (focused ? 2 : 1.5))
        )
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Decorative

struct DotPattern: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 3
            while y < size.height {
                var x: CGFloat = 3
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.9)))
                    x += 8
                }
                y += 8
            }
        }
        .opacity(0.09)
        .allowsHitTesting(false)
    }
}

/// Yellow tape strip that scrolls, like the site's marquee.
struct MarqueeTape: View {
    private let segment = "✦ SILENCE CUTS  ✦ WORD CAPTIONS  ✦ MEMES & LOGOS  ✦ MUSIC & SFX  ✦ 9:16 EXPORT  "
    private let width: CGFloat = 640

    var body: some View {
        // The wide scrolling row lives in an overlay so it can't influence the layout width.
        Color.clear
            .frame(height: 44)
            .overlay(alignment: .leading) {
                TimelineView(.animation) { tl in
                    let x = -CGFloat((tl.date.timeIntervalSinceReferenceDate * 32).truncatingRemainder(dividingBy: Double(width)))
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in
                            Text(segment).font(.mono(13, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                                .fixedSize()
                                .frame(width: width, alignment: .leading)
                        }
                    }
                    .offset(x: x)
                }
            }
            .background(Theme.yellow)
            .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }
            .clipped()
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.yellow)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * abs(sin(t * 3 - Double(i) * 0.6)))
                }
            }
        }
    }
}

// MARK: - Custom vector icons

enum IconKind { case play, upload, download, send, back, gear, close }

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
            case .close:
                var p = Path()
                p.move(to: pt(0.25, 0.25)); p.addLine(to: pt(0.75, 0.75))
                p.move(to: pt(0.75, 0.25)); p.addLine(to: pt(0.25, 0.75))
                stroke(p, 0.13)
            }
        }
        .frame(width: size, height: size)
    }
}
