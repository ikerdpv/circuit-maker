import SwiftUI

struct CircuitCanvas: View {
    @Bindable var state: AppState
    @FocusState private var focused: Bool

    private var drag: DragMode? {
        get { state.drag }
        nonmutating set { state.drag = newValue }
    }
    private var wireEnd: GP? {
        get { state.wireEnd }
        nonmutating set { state.wireEnd = newValue }
    }
    private var lastClick: (id: UUID, time: Date)? {
        get { state.lastClick }
        nonmutating set { state.lastClick = newValue }
    }

    var body: some View {
        let zoom = state.zoom
        let w = CGFloat(worldCols) * gridSize * zoom
        let h = CGFloat(worldRows) * gridSize * zoom

        // Se leen aquí para que SwiftUI redibuje cuando cambien.
        let circuit = state.circuit
        let result = state.result
        let selection = state.selection
        let showValues = state.showValues
        let animate = state.animate
        let colorByVoltage = state.colorByVoltage
        let hover = state.hover
        let preview: [(GP, GP)] = {
            if case .wire(let from)? = drag, let end = wireEnd { return Circuit.route(from, end) }
            return []
        }()
        let ghost: Component? = {
            guard case .place(let k) = state.tool, let hover, drag == nil else { return nil }
            let dir = Component.dirs[state.placeRot]
            return Component(kind: k, name: "", pos: hover - dir * (compLen / 2), rot: state.placeRot)
        }()
        let showHover: Bool = {
            if state.tool == .wire { return true }
            if state.tool == .select, let hover, circuit.terminalNear(hover.pt, radius: 1) != nil { return true }
            return false
        }()

        ZStack(alignment: .topLeading) {
            GridLayer(zoom: zoom)
            TimelineView(.animation(paused: !animate)) { tl in
                Canvas { ctx, _ in
                    var g = ctx
                    g.scaleBy(x: zoom, y: zoom)
                    Renderer(circuit: circuit, result: result, selection: selection,
                             time: tl.date.timeIntervalSinceReferenceDate,
                             showValues: showValues, animate: animate, colorByVoltage: colorByVoltage,
                             wirePreview: preview, ghost: ghost, hover: hover, showHover: showHover)
                        .draw(g)
                }
            }
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let loc): state.hover = GP.snap(scaled(loc))
            case .ended: state.hover = nil
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onChange(of: state.tool) { focused = true }
        .onAppear { focused = true }
    }

    private func scaled(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / state.zoom, y: p.y / state.zoom)
    }

    // MARK: Ratón

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if drag == nil {
                    focused = true
                    begin(scaled(v.startLocation))
                }
                update(scaled(v.location))
            }
            .onEnded { v in
                end(scaled(v.location))
                drag = nil
                wireEnd = nil
            }
    }

    private func begin(_ p: CGPoint) {
        let g = GP.snap(p)
        switch state.tool {
        case .wire:
            let start = state.circuit.terminalNear(p, radius: 10) ?? g
            drag = .wire(start)
            wireEnd = start
        case .select:
            if let t = state.circuit.terminalNear(p) {
                drag = .wire(t)
                wireEnd = t
            } else if let c = state.circuit.hitComponent(p) {
                state.selection = .comp(c.id)
                drag = .moveComp(c.id, origin: state.circuit, start: g, moved: false)
            } else if let w = state.circuit.hitWire(p) {
                state.selection = .wire(w.id)
                drag = .moveWire(w.id, origin: state.circuit, start: g, moved: false)
            } else {
                state.selection = nil
                drag = DragMode.none
            }
        case .delete, .place:
            drag = DragMode.none
        }
    }

    private func update(_ p: CGPoint) {
        let g = GP.snap(p)
        switch drag {
        case .wire?:
            wireEnd = g
        case .moveComp(let id, let origin, let start, let moved)?:
            let d = g - start
            if d == .zero && !moved { return }
            if !moved {
                state.checkpoint()
                drag = .moveComp(id, origin: origin, start: start, moved: true)
            }
            state.circuit = origin.movingComponent(id, by: d)
        case .moveWire(let id, let origin, let start, let moved)?:
            let d = g - start
            if d == .zero && !moved { return }
            if !moved {
                state.checkpoint()
                drag = .moveWire(id, origin: origin, start: start, moved: true)
            }
            state.circuit = origin.movingWire(id, by: d)
        default:
            break
        }
    }

    private func end(_ p: CGPoint) {
        let g = GP.snap(p)
        switch drag {
        case .wire(let from)?:
            if g != from {
                state.addWire(from, g)
            } else if state.tool == .select {
                if let c = state.circuit.hitComponent(p) { clicked(c) }
                else if let w = state.circuit.hitWire(p) { state.selection = .wire(w.id) }
                else { state.selection = nil }
            }
        case .moveComp(let id, _, _, let moved)?:
            if moved { state.cleanupWires() }
            else if let c = state.circuit.component(id) { clicked(c) }
        case .moveWire(_, _, _, let moved)?:
            if moved { state.cleanupWires() }
        default:
            switch state.tool {
            case .place(let k):
                state.place(k, center: g)
            case .delete:
                if let c = state.circuit.hitComponent(p) { state.delete(.comp(c.id)) }
                else if let w = state.circuit.hitWire(p) { state.delete(.wire(w.id)) }
            default:
                break
            }
        }
    }

    /// Clic sobre un componente: selecciona; doble clic en un interruptor lo abre o cierra.
    private func clicked(_ c: Component) {
        state.selection = .comp(c.id)
        let now = Date()
        if c.kind == .toggle, let last = lastClick, last.id == c.id, now.timeIntervalSince(last.time) < 0.4 {
            state.toggleSwitch(c.id)
            lastClick = nil
        } else {
            lastClick = (c.id, now)
        }
    }

    // MARK: Teclado

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) { return .ignored }
        switch press.key {
        case .delete, .deleteForward:
            state.deleteSelection(); return .handled
        case .escape:
            state.tool = .select; drag = nil; wireEnd = nil; return .handled
        case .space:
            if case .comp(let id)? = state.selection, state.component(id)?.kind == .toggle {
                state.toggleSwitch(id)
            }
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case "r": state.rotateSelection()
        case "w", "c": state.tool = .wire
        case "v", "m": state.tool = .select
        case "d", "b": state.tool = .delete
        case "1", "2", "3", "4", "5", "6":
            let i = Int(press.characters)! - 1
            state.tool = .place(Kind.allCases[i])
        default:
            return .ignored
        }
        return .handled
    }
}
