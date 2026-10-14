// Prueba de la app de Mac desde dentro: la app se manda a sí misma clics, arrastres y teclas
// (como si los hiciera una persona) y comprueba el resultado. No necesita permisos de
// accesibilidad. Solo se compila en la versión de prueba: ver tests/mac/run.sh.
#if SELFTEST
import AppKit

@MainActor
enum SelfTest {
    static var lines: [String] = []
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "OK    " : "FALLO ") + what)
        if !ok { failures += 1 }
    }

    static func start() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            await run()
            let out = ProcessInfo.processInfo.environment["SELFTEST_OUT"] ?? NSTemporaryDirectory() + "circuitmaker-selftest.txt"
            lines.append(failures == 0 ? "TODO BIEN" : "\(failures) FALLOS")
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    // MARK: Eventos sintéticos

    static var window: NSWindow { NSApp.windows.first { $0.contentView != nil && $0.isVisible }! }

    static func canvasView(_ v: NSView) -> NSView? {
        if let s = v as? NSScrollView, let d = s.documentView, d.frame.width > 2000 { return d }
        for sub in v.subviews { if let r = canvasView(sub) { return r } }
        return nil
    }

    /// Punto de la cuadrícula → coordenadas de la ventana.
    static func point(_ x: Double, _ y: Double) -> NSPoint {
        let doc = canvasView(window.contentView!)!
        let z = AppState.shared.zoom
        var p = NSPoint(x: x * 20 * z, y: y * 20 * z)
        if !doc.isFlipped { p.y = doc.bounds.height - p.y }
        return doc.convert(p, to: nil)
    }

    static func pause(_ ms: Int = 40) async { try? await Task.sleep(for: .milliseconds(ms)) }

    static func mouse(_ type: NSEvent.EventType, _ p: NSPoint, _ flags: NSEvent.ModifierFlags = []) {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags,
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        NSApp.postEvent(e, atStart: false)
    }

    static func drag(from a: (Double, Double), to b: (Double, Double), _ flags: NSEvent.ModifierFlags = []) async {
        let p = point(a.0, a.1), q = point(b.0, b.1)
        mouse(.leftMouseDown, p, flags); await pause()
        for i in 1...8 {
            let t = Double(i) / 8
            mouse(.leftMouseDragged, NSPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t), flags)
            await pause(20)
        }
        mouse(.leftMouseUp, q, flags); await pause(150)
    }

    static func click(_ x: Double, _ y: Double, _ flags: NSEvent.ModifierFlags = []) async {
        let p = point(x, y)
        mouse(.leftMouseDown, p, flags); await pause()
        mouse(.leftMouseUp, p, flags); await pause(150)
    }

    static func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) async {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                 isARepeat: false, keyCode: code)!
        NSApp.postEvent(e, atStart: false)
        await pause(150)
    }

    static func names(_ s: Set<Selection>) -> [String] {
        AppState.shared.circuit.components.filter { s.contains(.comp($0.id)) }.map(\.name).sorted()
    }

    static func comp(_ name: String) -> Component? { AppState.shared.circuit.components.first { $0.name == name } }

    static func textField(_ v: NSView, _ value: String) -> NSTextField? {
        if let t = v as? NSTextField, t.isEditable, t.stringValue == value { return t }
        for sub in v.subviews { if let r = textField(sub, value) { return r } }
        return nil
    }

    // MARK: Prueba

    static func run() async {
        let s = AppState.shared
        s.loadExample(0)
        s.zoom = 1
        await pause(300)
        let total = s.circuit.components.count
        lines.append("Ejemplo en serie: \(total) piezas, \(s.circuit.wires.count) cables")

        // 1. Rectángulo de selección arrastrando sobre un hueco
        await drag(from: (8, 7), to: (21, 12))
        check(names(s.selection) == ["E1", "R1", "S1"], "rectángulo selecciona E1, R1 y S1 (\(names(s.selection)))")
        check(s.marquee == nil, "el rectángulo desaparece al soltar")

        // 2. Borrar con ⌫ (keyCode 51, carácter U+007F, como el teclado de verdad)
        let wiresBefore = s.circuit.wires.count
        await key(51, "\u{7F}")
        check(s.circuit.components.count == total - 3, "⌫ borra las 3 piezas seleccionadas")
        check(s.circuit.wires.count < wiresBefore, "⌫ borra también los cables seleccionados")

        // 3. ⌘Z las recupera
        await key(6, "z", .command)
        check(s.circuit.components.count == total, "⌘Z recupera lo borrado")

        // 4. Clic en L1 y ⌘+clic en R1
        await click(28, 12)
        check(names(s.selection) == ["L1"], "clic selecciona solo L1")
        await click(22, 10, .command)
        check(names(s.selection) == ["L1", "R1"], "⌘+clic añade R1 (\(names(s.selection)))")
        await click(22, 10, .command)
        check(names(s.selection) == ["L1"], "⌘+clic otra vez quita R1")
        await click(22, 10, .command)

        // 5. Arrastrar una de las dos mueve las dos
        let l1 = comp("L1")!.pos, r1 = comp("R1")!.pos
        await drag(from: (28, 12), to: (31, 12))
        check(comp("L1")!.pos == l1 + GP(x: 3, y: 0) && comp("R1")!.pos == r1 + GP(x: 3, y: 0), "arrastrar L1 mueve L1 y R1 juntas")
        check(s.result.error == nil && abs(s.result.comps[comp("E1")!.id]!.i) > 0.1, "el circuito sigue conectado tras moverlas (los cables las siguen)")

        // 6. R gira las dos
        let rots = (comp("L1")!.rot, comp("R1")!.rot)
        await key(15, "r")
        check(comp("L1")!.rot == (rots.0 + 1) % 4 && comp("R1")!.rot == (rots.1 + 1) % 4, "R gira las dos")
        await key(6, "z", .command)
        await key(6, "z", .command)

        // 7. ⌘A y Esc
        await key(0, "a", .command)
        check(s.selection.count == s.circuit.components.count + s.circuit.wires.count, "⌘A selecciona todo")
        await key(53, "\u{1B}")
        check(s.selection.isEmpty, "Esc quita la selección")

        // 8. ⇧+rectángulo añade a lo que ya había
        await click(28, 12)
        await drag(from: (8, 7), to: (11, 15), .shift)
        check(names(s.selection) == ["E1", "L1"], "⇧+rectángulo añade E1 a L1 (\(names(s.selection)))")

        // 9. Supr (fn+⌫, keyCode 117)
        await key(117, "\u{F728}")
        check(comp("E1") == nil && comp("L1") == nil, "Supr (fn+⌫) borra la selección")
        await key(6, "z", .command)

        // 10. Escribiendo en un campo de texto, ⌫ borra texto y no piezas
        await click(22, 10)
        await pause(300)
        if let field = textField(window.contentView!, "R1") {
            window.makeFirstResponder(field)
            await pause(100)
            await key(51, "\u{7F}")
            await pause(100)
            check(comp("R1") != nil || s.circuit.components.count == total, "⌫ dentro del campo de nombre NO borra la pieza")
            check(field.stringValue != "R1", "⌫ dentro del campo de nombre borra texto (queda «\(field.stringValue)»)")
            window.makeFirstResponder(nil)
        } else {
            check(false, "no encuentro el campo de nombre de R1 en el panel")
        }
        check(s.circuit.components.count == total, "siguen las \(total) piezas")
    }
}
#endif
