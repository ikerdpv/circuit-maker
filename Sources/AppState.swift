import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Tool: Equatable {
    case select, wire, delete
    case place(Kind)
}

enum DragMode {
    case wire(GP)
    case moveComp(UUID, origin: Circuit, start: GP, moved: Bool)
    case moveWire(UUID, origin: Circuit, start: GP, moved: Bool)
    case none
}

enum Selection: Equatable {
    case comp(UUID)
    case wire(UUID)
}

@MainActor
@Observable
final class AppState {
    var circuit = Circuit.example(0) {
        didSet { result = Solver.solve(circuit) }
    }
    private(set) var result = SolveResult()

    var tool: Tool = .select
    var selection: Selection?
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
        switch selection {
        case .comp(let id)?: if circuit.component(id) == nil { selection = nil }
        case .wire(let id)?: if !circuit.wires.contains(where: { $0.id == id }) { selection = nil }
        case nil: break
        }
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
        selection = .comp(id)
    }

    func addWire(_ a: GP, _ b: GP) {
        checkpoint()
        circuit.wire(a, b)
    }

    func delete(_ sel: Selection) {
        checkpoint()
        switch sel {
        case .comp(let id): circuit.components.removeAll { $0.id == id }
        case .wire(let id): circuit.wires.removeAll { $0.id == id }
        }
        if selection == sel { selection = nil }
    }

    func deleteSelection() {
        if let s = selection { delete(s) }
    }

    func rotateSelection() {
        if case .place = tool { placeRot = (placeRot + 1) % 4; return }
        if case .comp(let id)? = selection { update(id) { $0.rotate() } }
    }

    func toggleSwitch(_ id: UUID) {
        update(id) { $0.closed.toggle() }
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
        selection = nil
    }

    func loadExample(_ n: Int) {
        checkpoint()
        circuit = .example(n)
        fileURL = nil
        selection = nil
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
            selection = nil
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
