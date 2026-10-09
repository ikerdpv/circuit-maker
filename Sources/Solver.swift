import Foundation

struct ElemResult {
    var va: Double
    var vb: Double
    /// Corriente convencional que circula de `a` a `b` por dentro del componente.
    var i: Double
    var v: Double { va - vb }
    /// Potencia absorbida (negativa si el componente entrega energía).
    var p: Double { v * i }
}

struct WireSeg {
    var wireID: UUID
    var a: GP
    var b: GP
    var i: Double
    var va: Double
    var vb: Double
}

struct SolveResult {
    var comps: [UUID: ElemResult] = [:]
    var segs: [WireSeg] = []
    var nodeV: [GP: Double] = [:]
    /// Nº de conexiones en cada punto (para dibujar uniones y bornes sueltos).
    var degree: [GP: Int] = [:]
    var error: String?
    var warnings: [String] = []
    var ground: GP?
    var groundName: String?
    var vmax: Double = 0
}

/// Análisis nodal modificado (MNA) en corriente continua.
enum Solver {
    static let rWire = 1e-3
    static let rVoltmeter = 1e7
    static let gmin = 1e-9

    /// `p` está estrictamente dentro del segmento a-b.
    static func onSegment(_ p: GP, _ a: GP, _ b: GP) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx * (p.y - a.y) - dy * (p.x - a.x) != 0 { return false }
        let dot = (p.x - a.x) * dx + (p.y - a.y) * dy
        return dot > 0 && dot < dx * dx + dy * dy
    }

    static func solve(_ c: Circuit) -> SolveResult {
        var res = SolveResult()
        var pts = Set<GP>()
        for k in c.components { pts.insert(k.a); pts.insert(k.b) }
        for w in c.wires where w.a != w.b { pts.insert(w.a); pts.insert(w.b) }
        if pts.isEmpty { return res }

        // Trocea los cables en los puntos donde otro elemento se apoya (uniones en T).
        var pieces: [(id: UUID, a: GP, b: GP)] = []
        for w in c.wires where w.a != w.b {
            let inner = pts.filter { onSegment($0, w.a, w.b) }.sorted {
                abs($0.x - w.a.x) + abs($0.y - w.a.y) < abs($1.x - w.a.x) + abs($1.y - w.a.y)
            }
            var prev = w.a
            for q in inner + [w.b] { pieces.append((w.id, prev, q)); prev = q }
        }
        for k in c.components { res.degree[k.a, default: 0] += 1; res.degree[k.b, default: 0] += 1 }
        for p in pieces { res.degree[p.a, default: 0] += 1; res.degree[p.b, default: 0] += 1 }

        // Numeración de nodos. El 0 es la referencia (borne − de la primera pila).
        let sorted = pts.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        let firstBattery = c.components.first { $0.kind == .battery }
        let ground = firstBattery?.b ?? sorted[0]
        res.ground = ground
        res.groundName = firstBattery?.name
        var idx: [GP: Int] = [ground: 0]
        var n = 1
        for p in sorted where p != ground { idx[p] = n; n += 1 }

        var rs: [(n1: Int, n2: Int, r: Double)] = []
        var vs: [(n1: Int, n2: Int, v: Double)] = []
        var compR: [UUID: Int] = [:]
        var compV: [UUID: Int] = [:]

        for k in c.components {
            let na = idx[k.a]!, nb = idx[k.b]!
            switch k.kind {
            case .battery:
                compV[k.id] = vs.count
                if k.internalR > 1e-9 {
                    let mid = n; n += 1
                    vs.append((na, mid, k.voltage))
                    rs.append((mid, nb, k.internalR))
                } else {
                    vs.append((na, nb, k.voltage))
                }
            case .resistor:
                compR[k.id] = rs.count; rs.append((na, nb, max(k.resistance, 1e-6)))
            case .bulb:
                compR[k.id] = rs.count; rs.append((na, nb, k.bulbR))
            case .toggle:
                if k.closed { compR[k.id] = rs.count; rs.append((na, nb, rWire)) }
            case .ammeter:
                compR[k.id] = rs.count; rs.append((na, nb, rWire))
            case .voltmeter:
                compR[k.id] = rs.count; rs.append((na, nb, rVoltmeter))
            }
        }
        let firstPiece = rs.count
        for p in pieces { rs.append((idx[p.a]!, idx[p.b]!, rWire)) }

        let nn = n - 1
        let size = nn + vs.count
        var A = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        var z = [Double](repeating: 0, count: size)
        for k in 0..<nn { A[k][k] += gmin }
        for r in rs {
            let g = 1 / r.r
            if r.n1 > 0 { A[r.n1 - 1][r.n1 - 1] += g }
            if r.n2 > 0 { A[r.n2 - 1][r.n2 - 1] += g }
            if r.n1 > 0 && r.n2 > 0 {
                A[r.n1 - 1][r.n2 - 1] -= g
                A[r.n2 - 1][r.n1 - 1] -= g
            }
        }
        for (m, s) in vs.enumerated() {
            let row = nn + m
            if s.n1 > 0 { A[s.n1 - 1][row] += 1; A[row][s.n1 - 1] += 1 }
            if s.n2 > 0 { A[s.n2 - 1][row] -= 1; A[row][s.n2 - 1] -= 1 }
            z[row] = s.v
        }

        guard let x = gauss(A, z), x.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else {
            res.error = "No se puede resolver: hay pilas conectadas directamente entre sí (en paralelo o en bucle sin nada en medio). Revisa las conexiones."
            return res
        }
        func V(_ node: Int) -> Double { node == 0 ? 0 : x[node - 1] }

        for k in c.components {
            let va = V(idx[k.a]!), vb = V(idx[k.b]!)
            var i = 0.0
            if let m = compV[k.id] { i = x[nn + m] }
            else if let r = compR[k.id] { i = (va - vb) / rs[r].r }
            res.comps[k.id] = ElemResult(va: va, vb: vb, i: i)
        }
        for (j, p) in pieces.enumerated() {
            let r = rs[firstPiece + j]
            let va = V(r.n1), vb = V(r.n2)
            res.segs.append(WireSeg(wireID: p.id, a: p.a, b: p.b, i: (va - vb) / r.r, va: va, vb: vb))
        }
        for (p, k) in idx {
            res.nodeV[p] = V(k)
            res.vmax = max(res.vmax, abs(V(k)))
        }

        for k in c.components {
            guard let r = res.comps[k.id] else { continue }
            switch k.kind {
            case .battery where abs(r.i) > 50:
                res.warnings.append("¡Cortocircuito! Por \(k.name) circulan \(fmt(abs(r.i), "A")). Falta una resistencia o una bombilla en el camino.")
            case .bulb where r.p > 1.5 * k.ratedP:
                res.warnings.append("\(k.name) recibe \(fmt(r.p, "W")) y su potencia nominal es \(fmt(k.ratedP, "W")): se fundiría.")
            case .ammeter where abs(r.i) > 50:
                res.warnings.append("\(k.name) mide una corriente enorme: ¿está conectado en paralelo? El amperímetro va en serie.")
            default:
                break
            }
        }
        return res
    }

    /// Eliminación gaussiana con pivoteo parcial.
    static func gauss(_ A0: [[Double]], _ b0: [Double]) -> [Double]? {
        var A = A0, b = b0
        let n = b.count
        if n == 0 { return [] }
        for col in 0..<n {
            var piv = col
            var best = abs(A[col][col])
            for r in (col + 1)..<n where abs(A[r][col]) > best { best = abs(A[r][col]); piv = r }
            if best < 1e-13 { return nil }
            if piv != col { A.swapAt(piv, col); b.swapAt(piv, col) }
            let pivotRow = A[col]
            for r in (col + 1)..<n {
                let f = A[r][col] / pivotRow[col]
                if f == 0 { continue }
                for k in col..<n { A[r][k] -= f * pivotRow[k] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for k in (r + 1)..<n { s -= A[r][k] * x[k] }
            x[r] = s / A[r][r]
        }
        return x
    }
}

/// Formatea un valor con prefijo SI: 0.045 A → "45 mA".
func fmt(_ v: Double, _ unit: String, sig: Int = 3) -> String {
    guard v.isFinite else { return "— \(unit)" }
    let a = abs(v)
    let zero: Double = unit == "A" ? 1e-7 : 1e-6
    if a < zero { return "0 \(unit)" }
    let scales: [(Double, String)] = [(1e9, "G"), (1e6, "M"), (1e3, "k"), (1, ""), (1e-3, "m"), (1e-6, "µ"), (1e-9, "n")]
    var chosen = scales.last!
    for s in scales where a >= s.0 * 0.99995 { chosen = s; break }
    let scaled = v / chosen.0
    let mag = Int(floor(log10(abs(scaled))))
    let dec = max(0, sig - 1 - mag)
    var s = String(format: "%.\(dec)f", scaled)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if Locale.current.decimalSeparator == "," { s = s.replacingOccurrences(of: ".", with: ",") }
    return "\(s) \(chosen.1)\(unit)"
}
