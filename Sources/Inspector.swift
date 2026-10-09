import SwiftUI

struct Inspector: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let e = state.result.error {
                    Notice(text: e, color: .red, icon: "exclamationmark.octagon.fill")
                }
                ForEach(state.result.warnings, id: \.self) {
                    Notice(text: $0, color: .orange, icon: "exclamationmark.triangle.fill")
                }

                switch state.selection {
                case .comp(let id)?:
                    ComponentInspector(state: state, id: id).id(id)
                case .wire(let id)?:
                    WireInspector(state: state, id: id)
                case nil:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nada seleccionado").font(.headline)
                        Text("Haz clic en un componente para ver y cambiar sus valores. Elige una pieza a la izquierda y haz clic en el lienzo para colocarla; arrastra desde un borne para unirla con un cable.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                SummaryView(state: state)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Notice: View {
    let text: String
    let color: Color
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ValueRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium).textSelection(.enabled)
        }
        .font(.callout)
    }
}

struct NumField: View {
    let label: String
    @Binding var value: Double
    let unit: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number.precision(.significantDigits(1...6)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).frame(width: 18, alignment: .leading).foregroundStyle(.secondary)
        }
    }
}

struct ComponentInspector: View {
    @Bindable var state: AppState
    let id: UUID

    var body: some View {
        if let c = state.component(id) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SymbolIcon(kind: c.kind).frame(width: 46, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Nombre", text: bind(\.name, c, checkpoint: false))
                            .textFieldStyle(.plain).font(.title3.bold())
                        Text(c.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) { params(c) }.padding(4)
                } label: { Text("Parámetros") }

                if state.result.error == nil, let r = state.result.comps[id] {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) { results(c, r) }.padding(4)
                    } label: { Text("Resultados") }
                }

                HStack {
                    Button { state.rotateSelection() } label: { Label("Girar", systemImage: "rotate.right") }
                    Spacer()
                    Button(role: .destructive) { state.deleteSelection() } label: { Label("Eliminar", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: Bindings

    private func bind<T>(_ kp: WritableKeyPath<Component, T>, _ c: Component, checkpoint: Bool = true) -> Binding<T> {
        Binding(get: { state.component(id)?[keyPath: kp] ?? c[keyPath: kp] },
                set: { v in state.update(id, checkpoint: checkpoint) { $0[keyPath: kp] = v } })
    }

    private func num(_ kp: WritableKeyPath<Component, Double>, _ c: Component, min lo: Double, live: Bool = false) -> Binding<Double> {
        Binding(get: { state.component(id)?[keyPath: kp] ?? c[keyPath: kp] },
                set: { v in state.update(id, checkpoint: !live) { $0[keyPath: kp] = v.isFinite ? max(lo, v) : lo } })
    }

    private func logResistance(_ c: Component) -> Binding<Double> {
        Binding(get: { log10(max(1, state.component(id)?.resistance ?? c.resistance)) },
                set: { v in state.update(id, checkpoint: false) { $0.resistance = roundNice(pow(10, v)) } })
    }

    private func presets(_ values: [Double], unit: String, _ kp: WritableKeyPath<Component, Double>) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { v in
                Button(fmt(v, unit)) { state.update(id) { $0[keyPath: kp] = v } }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Parámetros

    @ViewBuilder
    private func params(_ c: Component) -> some View {
        switch c.kind {
        case .battery:
            NumField(label: "Tensión", value: num(\.voltage, c, min: -10000), unit: "V")
            Slider(value: num(\.voltage, c, min: 0, live: true), in: 0...48, step: 0.5) { editing in
                if editing { state.checkpoint() }
            }
            presets([1.5, 4.5, 9, 12, 24], unit: "V", \.voltage)
            NumField(label: "Resistencia interna", value: num(\.internalR, c, min: 0), unit: "Ω")
            Hint("El borne + es el de la placa larga. 0 Ω = pila ideal.")
        case .resistor:
            NumField(label: "Resistencia", value: num(\.resistance, c, min: 1e-3), unit: "Ω")
            Slider(value: logResistance(c), in: 0...6) { editing in
                if editing { state.checkpoint() }
            }
            presets([10, 100, 220, 1000, 10000], unit: "Ω", \.resistance)
        case .bulb:
            NumField(label: "Tensión nominal", value: num(\.ratedV, c, min: 0.01), unit: "V")
            NumField(label: "Potencia nominal", value: num(\.ratedP, c, min: 0.001), unit: "W")
            ValueRow("Resistencia del filamento", fmt(c.bulbR, "Ω"))
            Hint("Brilla al 100 % cuando recibe su potencia nominal. Por encima del 150 % se funde.")
        case .toggle:
            Toggle("Cerrado (deja pasar la corriente)", isOn: bind(\.closed, c))
            Hint("También puedes hacer doble clic sobre él o pulsar la barra espaciadora.")
        case .ammeter:
            Hint("Amperímetro ideal (resistencia ≈ 0). Mide la corriente: se conecta en serie.")
        case .voltmeter:
            Hint("Voltímetro ideal (resistencia muy alta). Mide la tensión: se conecta en paralelo.")
        }
    }

    // MARK: Resultados

    @ViewBuilder
    private func results(_ c: Component, _ r: ElemResult) -> some View {
        switch c.kind {
        case .battery:
            ValueRow("Tensión en bornes", fmt(r.v, "V"))
            ValueRow("Corriente", fmt(abs(r.i), "A"))
            ValueRow(r.p <= 0 ? "Potencia entregada" : "Potencia absorbida", fmt(abs(r.p), "W"))
            if c.internalR > 0 {
                ValueRow("Pérdidas internas", fmt(r.i * r.i * c.internalR, "W"))
            }
        case .ammeter:
            BigReading(value: fmt(abs(r.i), "A"))
        case .voltmeter:
            BigReading(value: fmt(r.v, "V"))
        case .toggle:
            if c.closed {
                ValueRow("Corriente", fmt(abs(r.i), "A"))
            } else {
                ValueRow("Tensión entre bornes", fmt(abs(r.v), "V"))
                ValueRow("Corriente", fmt(0, "A"))
            }
        case .resistor, .bulb:
            ValueRow("Tensión (V)", fmt(abs(r.v), "V"))
            ValueRow("Intensidad (I)", fmt(abs(r.i), "A"))
            ValueRow("Potencia (P)", fmt(abs(r.p), "W"))
            let R = c.kind == .bulb ? c.bulbR : c.resistance
            ValueRow("Ley de Ohm", "\(fmt(abs(r.i), "A")) × \(fmt(R, "Ω")) = \(fmt(abs(r.i) * R, "V"))")
            if c.kind == .bulb {
                let pct = r.p / c.ratedP
                ProgressView(value: min(1, max(0, pct))) {
                    Text(pct > 1.5 ? "¡Se fundiría!" : "Brillo: \(Int((pct * 100).rounded())) % de su potencia nominal")
                        .font(.caption)
                        .foregroundStyle(pct > 1.5 ? .red : .secondary)
                }
                .tint(pct > 1.5 ? .red : .yellow)
            }
        }
    }
}

private func roundNice(_ v: Double) -> Double {
    guard v > 0 else { return v }
    let f = pow(10, floor(log10(v)) - 1)
    return (v / f).rounded() * f
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct BigReading: View {
    let value: String
    var body: some View {
        Text(value)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(nsColor: .systemBlue))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

struct WireInspector: View {
    var state: AppState
    let id: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cable").font(.title3.bold())
            if state.result.error == nil {
                let segs = state.result.segs.filter { $0.wireID == id }
                if let s = segs.first {
                    ValueRow("Tensión del cable", fmt(s.va, "V"))
                    ValueRow("Corriente", fmt(segs.map { abs($0.i) }.max() ?? 0, "A"))
                }
            }
            Hint("Un cable ideal une puntos con la misma tensión. Si pasa por el borne de un componente, queda conectado a él.")
            Button(role: .destructive) { state.deleteSelection() } label: { Label("Eliminar", systemImage: "trash") }
        }
    }
}

struct SummaryView: View {
    var state: AppState

    var body: some View {
        let comps = state.circuit.components
        let res = state.result
        VStack(alignment: .leading, spacing: 8) {
            Text("Todo el circuito").font(.headline)
            if comps.isEmpty {
                Hint("Añade componentes desde la barra de la izquierda.")
            } else if res.error == nil {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        Text("")
                        Text("V")
                        Text("I")
                        Text("P")
                    }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    Divider()
                    ForEach(comps) { c in
                        GridRow {
                            Text(c.name).bold()
                            Text(fmt(abs(res.comps[c.id]?.v ?? 0), "V"))
                            Text(fmt(abs(res.comps[c.id]?.i ?? 0), "A"))
                            Text(c.kind == .ammeter || c.kind == .voltmeter ? "—" : fmt(abs(res.comps[c.id]?.p ?? 0), "W"))
                        }
                        .font(.callout.monospacedDigit())
                        .contentShape(Rectangle())
                        .onTapGesture { state.selection = .comp(c.id) }
                    }
                }
                Divider()
                let batteries = comps.filter { $0.kind == .battery }
                let supplied = batteries.reduce(0.0) { $0 + max(0, -(res.comps[$1.id]?.p ?? 0)) }
                let consumed = comps.filter { $0.kind != .battery }.reduce(0.0) { $0 + max(0, res.comps[$1.id]?.p ?? 0) }
                ValueRow("Potencia entregada", fmt(supplied, "W"))
                ValueRow("Potencia consumida", fmt(consumed, "W"))
                if batteries.count == 1, let r = res.comps[batteries[0].id], abs(r.i) > 1e-7 {
                    ValueRow("Resistencia equivalente", fmt(abs(r.v / r.i), "Ω"))
                }
                if let g = res.groundName {
                    Hint("Las tensiones de nodo (abajo, al pasar el ratón) se miden respecto al borne − de \(g).")
                }
            }
        }
    }
}
