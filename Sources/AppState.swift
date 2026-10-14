import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Tool: Equatable {
    case select, wire, delete
    case place(Kind)
}

/// Qué hace un clic con modificador sobre una pieza (como en las carpetas).
enum ClickMode {
    case replace   // clic normal: selecciona solo esa
    case toggle    // ⌘+clic: la añade o la quita
    case add       // ⇧+clic: la añade
}

enum DragMode {
    case wire(GP)
    /// Arrastrar elementos. `item` es el que se pulsó; si no se llega a mover, es un clic.
    case move(origin: Circuit, items: Set<Selection>, start: GP, moved: Bool, item: Selection, click: ClickMode)
    /// Rectángulo de selección desde `start`; `base` es lo que ya estaba seleccionado (con ⌘ o ⇧).
    case marquee(start: CGPoint, base: Set<Selection>)
    case none
}

@MainActor
@Observable
final class AppState {
    var circuit = Circuit.example(0) {
        didSet { result = Solver.solve(circuit) }
    }
    private(set) var result = SolveResult()

    var tool: Tool = .select
    var selection: Set<Selection> = []
    /// Rectángulo de selección que se está dibujando.
    var marquee: CGRect?
    var placeRot = 0
    var showValues = true
    var animate = true
    var colorByVoltage = true
    var zoom: CGFloat = 1
    var hover: GP?
    var fileURL: URL?

    // Estado temporal de la interacción con el ratón en el lienzo.
    var drag: DragMode?
    var wireEnd: GP?
    @ObservationIgnored var lastClick: (id: UUID, time: Date)?

    static let shared = AppState()

    private var undoStack: [Circuit] = []
    private var redoStack: [Circuit] = []

    init() { result = Solver.solve(circuit) }

    // MARK: Deshacer

    func checkpoint() {
        undoStack.append(circuit)
        if undoStack.count > 300 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(circuit)
        circuit = last
        validateSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(circuit)
        circuit = next
        validateSelection()
    }

    private func validateSelection() {
        selection = selection.filter { circuit.contains($0) }
    }

    // MARK: Selección

    /// El elemento seleccionado, si solo hay uno.
    var single: Selection? { selection.count == 1 ? selection.first : nil }

    var selectedComponentIDs: [UUID] {
        circuit.components.map(\.id).filter { selection.contains(.comp($0)) }
    }

    func selectAll() {
        tool = .select
        selection = circuit.allItems
    }

    // MARK: Edición

    func component(_ id: UUID) -> Component? { circuit.component(id) }

    func update(_ id: UUID, checkpoint cp: Bool = true, _ f: (inout Component) -> Void) {
        guard let i = circuit.components.firstIndex(where: { $0.id == id }) else { return }
        var c = circuit.components[i]
        f(&c)
        guard c != circuit.components[i] else { return }
        if cp { checkpoint() }
        circuit.components[i] = c
    }

    func place(_ kind: Kind, center: GP) {
        checkpoint()
        let dir = Component.dirs[placeRot]
        let id = circuit.add(kind, at: center - dir * (compLen / 2), rot: placeRot)
        selection = [.comp(id)]
    }

    func addWire(_ a: GP, _ b: GP) {
        checkpoint()
        circuit.wire(a, b)
    }

    func delete(_ items: Set<Selection>) {
        guard !items.isEmpty else { return }
        checkpoint()
        circuit.components.removeAll { items.contains(.comp($0.id)) }
        circuit.wires.removeAll { items.contains(.wire($0.id)) }
        selection.subtract(items)
    }

    func deleteSelection() {
        delete(selection)
    }

    /// Gira cada pieza seleccionada sobre su centro.
    func rotateSelection() {
        if case .place = tool { placeRot = (placeRot + 1) % 4; return }
        let ids = Set(selectedComponentIDs)
        guard !ids.isEmpty else { return }
        checkpoint()
        for i in circuit.components.indices where ids.contains(circuit.components[i].id) {
            circuit.components[i].rotate()
        }
    }

    func toggleSwitch(_ id: UUID) {
        update(id) { $0.closed.toggle() }
    }

    /// Abre o cierra todos los interruptores seleccionados.
    func toggleSelectedSwitches() {
        let ids = Set(selectedComponentIDs.filter { component($0)?.kind == .toggle })
        guard !ids.isEmpty else { return }
        checkpoint()
        for i in circuit.components.indices where ids.contains(circuit.components[i].id) {
            circuit.components[i].closed.toggle()
        }
    }

    // MARK: Teclado

    /// Atajos del lienzo. Se leen directamente de macOS (por código de tecla) para que funcionen
    /// tenga quien tenga el foco, salvo mientras se escribe en un campo de texto.
    func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Los monitores locales se llaman siempre en el hilo principal.
            nonisolated(unsafe) let e = event
            let handled = MainActor.assumeIsolated { AppState.shared.handleKey(e) }
            return handled ? nil : event
        }
    }

    func handleKey(_ e: NSEvent) -> Bool {
        guard let win = e.window, win.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        if win.firstResponder is NSText { return false }   // escribiendo en un campo
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods.contains(.command) {
            switch (e.keyCode, key) {
            case (_, "a"): selectAll(); return true
            case (51, _), (117, _): deleteSelection(); return true    // ⌘⌫, como en el Finder
            default: return false
            }
        }
        if mods.contains(.control) || mods.contains(.option) { return false }
        switch e.keyCode {
        case 51, 117:   // ⌫ y Supr (fn+⌫)
            deleteSelection(); return true
        case 53:        // Esc
            if tool == .select { selection = [] } else { tool = .select }
            drag = nil; wireEnd = nil; marquee = nil
            return true
        case 49:        // espacio
            toggleSelectedSwitches(); return true
        default:
            break
        }
        switch key {
        case "r": rotateSelection()
        case "w", "c": tool = .wire
        case "v", "m": tool = .select
        case "d", "b": tool = .delete
        case "1", "2", "3", "4", "5", "6": tool = .place(Kind.allCases[Int(key)! - 1])
        default: return false
        }
        return true
    }

    func cleanupWires() {
        circuit.wires.removeAll { $0.a == $0.b }
    }

    func zoomIn() { zoom = min(2.5, zoom + 0.25) }
    func zoomOut() { zoom = max(0.5, zoom - 0.25) }

    // MARK: Archivos

    func newFile() {
        checkpoint()
        circuit = Circuit()
        fileURL = nil
        selection = []
    }

    func loadExample(_ n: Int) {
        checkpoint()
        circuit = .example(n)
        fileURL = nil
        selection = []
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let c = try JSONDecoder().decode(Circuit.self, from: Data(contentsOf: url))
            checkpoint()
            circuit = c
            fileURL = url
            selection = []
        } catch {
            alert("No se pudo abrir el archivo", error)
        }
    }

    func save() {
        if let url = fileURL { write(url) } else { saveAs() }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Circuito.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(url)
    }

    private func write(_ url: URL) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(circuit).write(to: url)
            fileURL = url
        } catch {
            alert("No se pudo guardar el archivo", error)
        }
    }

    private func alert(_ msg: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = msg
        a.informativeText = error.localizedDescription
        a.runModal()
    }
}
