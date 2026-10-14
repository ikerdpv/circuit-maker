import SwiftUI
import AppKit

struct CircuitCanvas: View {
    @Bindable var state: AppState

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
        let marquee = state.marquee
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
                    Renderer(circuit: circuit, result: result, selection: selection, marquee: marquee,
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
    }

    private func scaled(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / state.zoom, y: p.y / state.zoom)
    }

    // MARK: Ratón

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if drag == nil {
                    // Al pulsar en el lienzo se termina de editar cualquier campo de texto.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    begin(scaled(v.startLocation))
                }
                update(scaled(v.location))
            }
            .onEnded { v in
                end(scaled(v.location))
                drag = nil
                wireEnd = nil
                state.marquee = nil
            }
    }

    private func begin(_ p: CGPoint) {
        let g = GP.snap(p)
        let mods = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags   // las del propio clic
        let click: ClickMode = mods.contains(.command) ? .toggle : mods.contains(.shift) ? .add : .replace
        switch state.tool {
        case .wire:
            let start = state.circuit.terminalNear(p, radius: 10) ?? g
            drag = .wire(start)
            wireEnd = start
        case .select:
            if click == .replace, let t = state.circuit.terminalNear(p) {
                drag = .wire(t)
                wireEnd = t
            } else if let item = state.circuit.hitItem(p) {
                // Como en las carpetas: pulsar sobre algo ya seleccionado conserva el grupo para arrastrarlo.
                if click == .replace && !state.selection.contains(item) { state.selection = [item] }
                drag = .move(origin: state.circuit, items: state.selection.union([item]), start: g,
                             moved: false, item: item, click: click)
            } else {
                // Hueco vacío: rectángulo de selección.
                let base = click == .replace ? [] : state.selection
                state.selection = base
                drag = .marquee(start: p, base: base)
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
        case .move(let origin, let items, let start, let moved, let item, let click)?:
            let d = g - start
            if d == .zero && !moved { return }
            if !moved {
                state.checkpoint()
                state.selection = items
                drag = .move(origin: origin, items: items, start: start, moved: true, item: item, click: click)
            }
            state.circuit = origin.moving(items, by: d)
        case .marquee(let start, let base)?:
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(p.x - start.x), height: abs(p.y - start.y))
            state.marquee = rect
            state.selection = base.union(state.circuit.items(in: rect))
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
                if let item = state.circuit.hitItem(p) { clicked(item, .replace) }
                else { state.selection = [] }
            }
        case .move(_, _, _, let moved, let item, let click)?:
            if moved { state.cleanupWires() } else { clicked(item, click) }
        case .marquee?:
            break
        default:
            switch state.tool {
            case .place(let k):
                state.place(k, center: g)
            case .delete:
                if let item = state.circuit.hitItem(p) { state.delete([item]) }
            default:
                break
            }
        }
    }

    /// Clic sin arrastrar. Doble clic en un interruptor lo abre o cierra.
    private func clicked(_ item: Selection, _ click: ClickMode) {
        switch click {
        case .replace: state.selection = [item]
        case .add: state.selection.insert(item)
        case .toggle:
            if state.selection.contains(item) { state.selection.remove(item) } else { state.selection.insert(item) }
            return
        }
        guard case .comp(let id) = item, let c = state.component(id) else { return }
        let now = Date()
        if c.kind == .toggle, let last = lastClick, last.id == id, now.timeIntervalSince(last.time) < 0.4 {
            state.toggleSwitch(id)
            lastClick = nil
        } else {
            lastClick = (id, now)
        }
    }
}
