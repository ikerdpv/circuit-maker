import Foundation
import CoreGraphics

/// Tamaño de una celda de la cuadrícula en puntos (sin zoom).
let gridSize: CGFloat = 20
/// Longitud de cada componente en celdas.
let compLen = 4
let worldCols = 160
let worldRows = 110

/// Punto de la cuadrícula.
struct GP: Hashable, Codable {
    var x: Int
    var y: Int

    static let zero = GP(x: 0, y: 0)
    static func + (l: GP, r: GP) -> GP { GP(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: GP, r: GP) -> GP { GP(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: GP, k: Int) -> GP { GP(x: l.x * k, y: l.y * k) }

    var pt: CGPoint { CGPoint(x: CGFloat(x) * gridSize, y: CGFloat(y) * gridSize) }

    static func snap(_ p: CGPoint) -> GP {
        GP(x: Int((p.x / gridSize).rounded()), y: Int((p.y / gridSize).rounded()))
    }
}

enum Kind: String, Codable, CaseIterable, Identifiable {
    case battery, resistor, bulb, toggle, ammeter, voltmeter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Pila"
        case .resistor: "Resistencia"
        case .bulb: "Bombilla"
        case .toggle: "Interruptor"
        case .ammeter: "Amperímetro"
        case .voltmeter: "Voltímetro"
        }
    }

    var withArticle: String {
        switch self {
        case .battery, .resistor, .bulb: "una \(title.lowercased())"
        default: "un \(title.lowercased())"
        }
    }

    var prefix: String {
        switch self {
        case .battery: "E"
        case .resistor: "R"
        case .bulb: "L"
        case .toggle: "S"
        case .ammeter: "A"
        case .voltmeter: "V"
        }
    }
}

struct Component: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: Kind
    var name: String
    /// Posición del borne `a` (en una pila, el borne +).
    var pos: GP
    /// Orientación en pasos de 90°: 0 → derecha, 1 → abajo, 2 → izquierda, 3 → arriba.
    var rot: Int = 0
    var voltage: Double = 9
    var internalR: Double = 0
    var resistance: Double = 100
    var ratedV: Double = 9
    var ratedP: Double = 2
    var closed: Bool = true

    static let dirs = [GP(x: 1, y: 0), GP(x: 0, y: 1), GP(x: -1, y: 0), GP(x: 0, y: -1)]

    var rotIndex: Int { ((rot % 4) + 4) % 4 }
    var dir: GP { Component.dirs[rotIndex] }
    var a: GP { pos }
    var b: GP { pos + dir * compLen }
    var isVertical: Bool { dir.x == 0 }
    var midPt: CGPoint { CGPoint(x: (a.pt.x + b.pt.x) / 2, y: (a.pt.y + b.pt.y) / 2) }

    /// Resistencia del filamento a partir de los valores nominales (R = V² / P).
    var bulbR: Double { max(ratedV * ratedV / max(ratedP, 1e-9), 1e-3) }

    /// Convierte un punto del sistema local del símbolo (eje x a lo largo del componente) a coordenadas del lienzo.
    func world(_ local: CGPoint) -> CGPoint {
        let d = CGPoint(x: CGFloat(dir.x), y: CGFloat(dir.y))
        let n = CGPoint(x: -d.y, y: d.x)
        return CGPoint(x: a.pt.x + local.x * d.x + local.y * n.x,
                       y: a.pt.y + local.x * d.y + local.y * n.y)
    }

    /// Gira 90° alrededor del centro.
    mutating func rotate() {
        let center = pos + dir * (compLen / 2)
        rot = (rotIndex + 1) % 4
        pos = center - dir * (compLen / 2)
    }
}

struct Wire: Identifiable, Codable, Equatable {
    var id = UUID()
    var a: GP
    var b: GP
}

struct Circuit: Codable, Equatable {
    var components: [Component] = []
    var wires: [Wire] = []

    func nextName(for kind: Kind) -> String {
        let names = Set(components.map(\.name))
        var n = 1
        while names.contains("\(kind.prefix)\(n)") { n += 1 }
        return "\(kind.prefix)\(n)"
    }

    @discardableResult
    mutating func add(_ kind: Kind, at pos: GP, rot: Int = 0, configure: (inout Component) -> Void = { _ in }) -> UUID {
        var c = Component(kind: kind, name: nextName(for: kind), pos: pos, rot: rot)
        configure(&c)
        components.append(c)
        return c.id
    }

    /// Añade un cable; si no es recto lo hace en forma de L.
    mutating func wire(_ a: GP, _ b: GP) {
        for (p, q) in Circuit.route(a, b) { addSegment(p, q) }
    }

    static func route(_ a: GP, _ b: GP) -> [(GP, GP)] {
        if a == b { return [] }
        if a.x == b.x || a.y == b.y { return [(a, b)] }
        let corner = GP(x: b.x, y: a.y)
        return [(a, corner), (corner, b)]
    }

    private mutating func addSegment(_ a: GP, _ b: GP) {
        if wires.contains(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }) { return }
        wires.append(Wire(a: a, b: b))
    }

    func component(_ id: UUID) -> Component? { components.first { $0.id == id } }

    // MARK: Edición

    func movingComponent(_ id: UUID, by d: GP) -> Circuit {
        var c = self
        guard let i = c.components.firstIndex(where: { $0.id == id }) else { return c }
        let oa = c.components[i].a, ob = c.components[i].b
        c.components[i].pos = c.components[i].pos + d
        // Los cables conectados a sus bornes le siguen.
        for j in c.wires.indices {
            if c.wires[j].a == oa || c.wires[j].a == ob { c.wires[j].a = c.wires[j].a + d }
            if c.wires[j].b == oa || c.wires[j].b == ob { c.wires[j].b = c.wires[j].b + d }
        }
        return c
    }

    func movingWire(_ id: UUID, by d: GP) -> Circuit {
        var c = self
        guard let i = c.wires.firstIndex(where: { $0.id == id }) else { return c }
        c.wires[i].a = c.wires[i].a + d
        c.wires[i].b = c.wires[i].b + d
        return c
    }

    // MARK: Selección con el ratón

    func hitComponent(_ p: CGPoint) -> Component? {
        var best: (Component, CGFloat)?
        for c in components {
            let d = distToSeg(p, c.a.pt, c.b.pt)
            if d < 16, d < (best?.1 ?? .infinity) { best = (c, d) }
        }
        return best?.0
    }

    func hitWire(_ p: CGPoint) -> Wire? {
        var best: (Wire, CGFloat)?
        for w in wires {
            let d = distToSeg(p, w.a.pt, w.b.pt)
            if d < 6, d < (best?.1 ?? .infinity) { best = (w, d) }
        }
        return best?.0
    }

    /// Borne de componente o extremo de cable cercano a `p`.
    func terminalNear(_ p: CGPoint, radius: CGFloat = 7) -> GP? {
        var pts: [GP] = []
        for c in components { pts.append(c.a); pts.append(c.b) }
        for w in wires { pts.append(w.a); pts.append(w.b) }
        var best: (GP, CGFloat)?
        for q in pts {
            let d = hypot(p.x - q.pt.x, p.y - q.pt.y)
            if d < radius, d < (best?.1 ?? .infinity) { best = (q, d) }
        }
        return best?.0
    }

    // MARK: Ejemplos

    static func example(_ n: Int) -> Circuit {
        var c = Circuit()
        func p(_ x: Int, _ y: Int) -> GP { GP(x: x, y: y) }
        switch n {
        case 1: // Paralelo
            c.add(.battery, at: p(10, 10), rot: 1)
            c.wire(p(10, 10), p(12, 10))
            c.add(.ammeter, at: p(12, 10))
            c.wire(p(16, 10), p(32, 10))
            c.add(.bulb, at: p(22, 10), rot: 1)
            c.add(.bulb, at: p(32, 10), rot: 1)
            c.wire(p(32, 14), p(10, 14))
        case 2: // Mixto
            c.add(.battery, at: p(10, 10), rot: 1) { $0.voltage = 12 }
            c.wire(p(10, 10), p(16, 10))
            c.add(.resistor, at: p(16, 10)) { $0.resistance = 47 }
            c.wire(p(20, 10), p(32, 10))
            c.add(.resistor, at: p(25, 10), rot: 1) { $0.resistance = 100 }
            c.add(.bulb, at: p(32, 10), rot: 1) { $0.ratedV = 12; $0.ratedP = 3 }
            c.wire(p(32, 14), p(10, 14))
            c.wire(p(32, 10), p(41, 10))
            c.add(.voltmeter, at: p(41, 10), rot: 1)
            c.wire(p(41, 14), p(32, 14))
        default: // Serie
            c.add(.battery, at: p(10, 10), rot: 1)
            c.wire(p(10, 10), p(13, 10))
            c.add(.toggle, at: p(13, 10))
            c.wire(p(17, 10), p(20, 10))
            c.add(.resistor, at: p(20, 10)) { $0.resistance = 10 }
            c.wire(p(24, 10), p(28, 10))
            c.add(.bulb, at: p(28, 10), rot: 1)
            c.wire(p(28, 14), p(22, 14))
            c.add(.ammeter, at: p(18, 14))
            c.wire(p(18, 14), p(10, 14))
            c.wire(p(28, 10), p(37, 10))
            c.add(.voltmeter, at: p(37, 10), rot: 1)
            c.wire(p(37, 14), p(28, 14))
        }
        return c
    }
}

func distToSeg(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let l2 = dx * dx + dy * dy
    if l2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}
