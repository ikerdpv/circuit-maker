import SwiftUI

/// Dibuja los símbolos (normas europeas) en coordenadas locales: el componente va de x = 0 a x = L sobre y = 0.
enum Symbol {
    static let L = CGFloat(compLen) * gridSize

    static func draw(_ g: GraphicsContext, kind: Kind, closed: Bool = true, brightness: Double = 0,
                     overload: Bool = false, colorA: Color = .primary, colorB: Color = .primary,
                     ink: Color = .primary, letter: Bool = false) {
        let m = L / 2
        let st = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        func seg(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ color: Color, _ w: CGFloat = 2) {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x1, y: y1))
            g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        func circle(_ cx: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: cx - r, y: -r, width: 2 * r, height: 2 * r))
        }

        switch kind {
        case .resistor:
            seg(0, 0, m - 16, 0, colorA)
            seg(m + 16, 0, L, 0, colorB)
            g.stroke(Path(CGRect(x: m - 16, y: -7, width: 32, height: 14)), with: .color(ink), style: st)

        case .bulb:
            if brightness > 0.01 {
                let rad = 14 + 28 * brightness
                g.fill(circle(m, rad), with: .radialGradient(
                    Gradient(colors: [Color.yellow.opacity(0.9 * brightness), Color.yellow.opacity(0)]),
                    center: CGPoint(x: m, y: 0), startRadius: 6, endRadius: rad))
                g.fill(circle(m, 13), with: .color(Color.yellow.opacity(0.3 + 0.65 * brightness)))
            }
            let col = overload ? Color.red : ink
            seg(0, 0, m - 13, 0, colorA)
            seg(m + 13, 0, L, 0, colorB)
            g.stroke(circle(m, 13), with: .color(col), style: st)
            let d: CGFloat = 9.2
            seg(m - d, -d, m + d, d, col)
            seg(m - d, d, m + d, -d, col)

        case .battery:
            seg(0, 0, m - 4, 0, colorA)
            seg(m + 4, 0, L, 0, colorB)
            seg(m - 4, -16, m - 4, 16, ink, 2.5)   // placa larga: +
            seg(m + 4, -8, m + 4, 8, ink, 5)       // placa corta: −

        case .toggle:
            seg(0, 0, m - 14, 0, colorA)
            seg(m + 14, 0, L, 0, colorB)
            g.fill(circle(m - 14, 2.8), with: .color(ink))
            g.fill(circle(m + 14, 2.8), with: .color(ink))
            if closed { seg(m - 14, 0, m + 14, 0, ink) } else { seg(m - 14, 0, m + 11, -15, ink) }

        case .ammeter, .voltmeter:
            seg(0, 0, m - 14, 0, colorA)
            seg(m + 14, 0, L, 0, colorB)
            g.stroke(circle(m, 14), with: .color(ink), style: st)
            if letter {
                g.draw(Text(kind == .ammeter ? "A" : "V").font(.system(size: 13, weight: .bold)),
                       at: CGPoint(x: m, y: 0))
            }
        }
    }
}

/// Icono pequeño de un componente (paleta e inspector).
struct SymbolIcon: View {
    let kind: Kind
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / (Symbol.L + 4), size.height / 40)
            var g = ctx
            g.translateBy(x: (size.width - Symbol.L * s) / 2, y: size.height / 2)
            g.scaleBy(x: s, y: s)
            Symbol.draw(g, kind: kind, brightness: kind == .bulb ? 0.6 : 0, letter: true)
        }
    }
}

/// Pinta el circuito completo para un instante de tiempo dado.
struct Renderer {
    let circuit: Circuit
    let result: SolveResult
    let selection: Selection?
    let time: Double
    let showValues: Bool
    let animate: Bool
    let colorByVoltage: Bool
    let wirePreview: [(GP, GP)]
    let ghost: Component?
    let hover: GP?
    let showHover: Bool

    private var ok: Bool { result.error == nil }
    private let L = Symbol.L
    private static let valueColor = Color(nsColor: .systemBlue)
    private static let dotColor = Color(red: 1, green: 0.62, blue: 0.05)

    func vColor(_ v: Double?) -> Color {
        guard let v, colorByVoltage, ok, result.vmax > 1e-6 else { return .primary }
        let t = min(1, max(0, abs(v) / result.vmax))
        return Color(hue: 0.62 * (1 - t), saturation: 0.8, brightness: 0.82)
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    func draw(_ ctx: GraphicsContext) {
        let wst = StrokeStyle(lineWidth: 2.5, lineCap: .round)

        // Cables
        if case .wire(let id)? = selection, let w = circuit.wires.first(where: { $0.id == id }) {
            ctx.stroke(line(w.a.pt, w.b.pt), with: .color(.accentColor.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
        if ok {
            for s in result.segs {
                ctx.stroke(line(s.a.pt, s.b.pt), with: .color(vColor((s.va + s.vb) / 2)), style: wst)
            }
        } else {
            for w in circuit.wires { ctx.stroke(line(w.a.pt, w.b.pt), with: .color(.primary), style: wst) }
        }

        // Componentes
        for c in circuit.components { drawComponent(ctx, c) }

        // Uniones y bornes sin conectar
        for (p, d) in result.degree {
            if d >= 3 {
                ctx.fill(circle(p.pt, 4), with: .color(vColor(result.nodeV[p])))
            } else if d == 1 {
                ctx.stroke(circle(p.pt, 3.5), with: .color(.red.opacity(0.7)), lineWidth: 1.5)
            }
        }

        // Corriente animada
        if animate && ok {
            for s in result.segs { dots(ctx, s.a.pt, s.b.pt, s.i) }
            for c in circuit.components where c.kind != .voltmeter {
                if let r = result.comps[c.id] { dots(ctx, c.a.pt, c.b.pt, r.i) }
            }
        }

        if showValues { for c in circuit.components { drawLabels(ctx, c) } }

        if let ghost { drawComponent(ctx, ghost, isGhost: true) }
        for (a, b) in wirePreview {
            ctx.stroke(line(a.pt, b.pt), with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
        }
        if showHover, let h = hover {
            ctx.stroke(circle(h.pt, 6), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    private func drawComponent(_ ctx: GraphicsContext, _ c: Component, isGhost: Bool = false) {
        var g = ctx
        if isGhost { g.opacity = 0.4 }
        let r = isGhost ? nil : result.comps[c.id]
        var local = g
        local.translateBy(x: c.a.pt.x, y: c.a.pt.y)
        local.rotate(by: .degrees(Double(c.rotIndex) * 90))

        if selection == .comp(c.id) {
            let box = Path(roundedRect: CGRect(x: -8, y: -22, width: L + 16, height: 44), cornerRadius: 9)
            local.fill(box, with: .color(.accentColor.opacity(0.08)))
            local.stroke(box, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }

        var bright = 0.0, over = false
        if c.kind == .bulb, let r, ok {
            bright = min(1, max(0, r.p / c.ratedP))
            over = r.p > 1.5 * c.ratedP
        }
        Symbol.draw(local, kind: c.kind, closed: c.closed, brightness: bright, overload: over,
                    colorA: ok ? vColor(r?.va) : .primary, colorB: ok ? vColor(r?.vb) : .primary)

        // Textos que no deben girar
        switch c.kind {
        case .ammeter, .voltmeter:
            g.draw(Text(c.kind == .ammeter ? "A" : "V").font(.system(size: 13, weight: .bold)), at: c.midPt)
        case .battery:
            let m = L / 2
            g.draw(Text("+").font(.system(size: 12, weight: .bold)), at: c.world(CGPoint(x: m - 13, y: -12)))
            g.draw(Text("−").font(.system(size: 12, weight: .bold)), at: c.world(CGPoint(x: m + 13, y: -12)))
        default:
            break
        }
    }

    private func paramText(_ c: Component) -> String {
        switch c.kind {
        case .battery: c.internalR > 0 ? "\(fmt(c.voltage, "V")) · r \(fmt(c.internalR, "Ω"))" : fmt(c.voltage, "V")
        case .resistor: fmt(c.resistance, "Ω")
        case .bulb: "\(fmt(c.ratedV, "V")) / \(fmt(c.ratedP, "W"))"
        case .toggle: c.closed ? "cerrado" : "abierto"
        case .ammeter, .voltmeter: ""
        }
    }

    private func resultText(_ c: Component) -> String? {
        guard ok, let r = result.comps[c.id] else { return nil }
        switch c.kind {
        case .battery: return "I = \(fmt(abs(r.i), "A"))"
        case .resistor, .bulb: return "\(fmt(abs(r.v), "V")) · \(fmt(abs(r.i), "A"))"
        case .toggle: return c.closed ? fmt(abs(r.i), "A") : fmt(abs(r.v), "V")
        case .ammeter: return fmt(abs(r.i), "A")
        case .voltmeter: return fmt(r.v, "V")
        }
    }

    private func drawLabels(_ ctx: GraphicsContext, _ c: Component) {
        let mid = c.midPt
        let isMeter = c.kind == .ammeter || c.kind == .voltmeter
        let title = Text(c.name).font(.system(size: 11, weight: .semibold))
            + Text(paramText(c).isEmpty ? "" : "  " + paramText(c)).font(.system(size: 11))
        let value = resultText(c).map {
            Text($0).font(.system(size: isMeter ? 13 : 11, weight: isMeter ? .bold : .medium).monospacedDigit())
                .foregroundStyle(Renderer.valueColor)
        }
        if c.isVertical {
            ctx.draw(title, at: CGPoint(x: mid.x + 22, y: mid.y - 2), anchor: .bottomLeading)
            if let value { ctx.draw(value, at: CGPoint(x: mid.x + 22, y: mid.y + 2), anchor: .topLeading) }
        } else {
            ctx.draw(title, at: CGPoint(x: mid.x, y: mid.y - 24), anchor: .bottom)
            if let value { ctx.draw(value, at: CGPoint(x: mid.x, y: mid.y + 22), anchor: .top) }
        }
    }

    private func dots(_ ctx: GraphicsContext, _ from: CGPoint, _ to: CGPoint, _ i: Double) {
        let ai = abs(i)
        guard ai > 1e-6 else { return }
        let len = hypot(to.x - from.x, to.y - from.y)
        guard len > 1 else { return }
        let speed = min(170, 22 * log10(1 + ai * 1000) + 6)
        let spacing: Double = 16
        let ux = (to.x - from.x) / len, uy = (to.y - from.y) / len
        var s = CGFloat((time * speed).truncatingRemainder(dividingBy: spacing))
        while s < len {
            let d = i > 0 ? s : len - s
            let p = CGPoint(x: from.x + ux * d, y: from.y + uy * d)
            ctx.fill(circle(p, 2.4), with: .color(Renderer.dotColor))
            s += CGFloat(spacing)
        }
    }
}

struct GridLayer: View {
    let zoom: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let step = gridSize * zoom
            var p = Path()
            var y: CGFloat = 0
            while y <= size.height {
                var x: CGFloat = 0
                while x <= size.width {
                    p.addRect(CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += step
                }
                y += step
            }
            ctx.fill(p, with: .color(.secondary.opacity(0.5)))
        }
    }
}
