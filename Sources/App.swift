import SwiftUI
import AppKit

@main
struct CircuitMakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let state = AppState.shared

    var body: some Scene {
        Window("Circuit Maker", id: "main") {
            ContentView(state: state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1300, height: 820)
        .commands { AppCommands(state: state) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Al abrir la app, busca actualizaciones en GitHub.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Updater.check(userInitiated: false)
        }
    }
}

struct ContentView: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            Palette(state: state).frame(width: 84)
            Divider()
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    CircuitCanvas(state: state)
                }
                .background(Color(nsColor: .textBackgroundColor))
                Divider()
                StatusBar(state: state)
            }
            Divider()
            Inspector(state: state).frame(width: 320)
        }
        .navigationTitle(state.fileURL?.deletingPathExtension().lastPathComponent ?? "Circuit Maker")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Circuito en serie") { state.loadExample(0) }
                    Button("Circuito en paralelo") { state.loadExample(1) }
                    Button("Circuito mixto") { state.loadExample(2) }
                } label: { Label("Ejemplos", systemImage: "books.vertical") }
                Button { state.zoomOut() } label: { Label("Alejar", systemImage: "minus.magnifyingglass") }
                Button { state.zoomIn() } label: { Label("Acercar", systemImage: "plus.magnifyingglass") }
                Toggle(isOn: $state.showValues) { Label("Valores", systemImage: "textformat.123") }
                    .help("Mostrar valores sobre el esquema")
                Toggle(isOn: $state.animate) { Label("Corriente", systemImage: "bolt.fill") }
                    .help("Animar el movimiento de la corriente")
                Toggle(isOn: $state.colorByVoltage) { Label("Colores", systemImage: "paintpalette") }
                    .help("Colorear los cables según su tensión (azul = 0 V, rojo = máxima)")
            }
        }
    }
}

struct Palette: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ToolButton(title: "Mover", key: "V", selected: state.tool == .select, action: { state.tool = .select }) {
                    Image(systemName: "cursorarrow").font(.system(size: 18))
                }
                ToolButton(title: "Cable", key: "W", selected: state.tool == .wire, action: { state.tool = .wire }) {
                    Image(systemName: "line.diagonal").font(.system(size: 18))
                }
                Divider().padding(.vertical, 2)
                ForEach(Array(Kind.allCases.enumerated()), id: \.element) { i, k in
                    ToolButton(title: k.title, key: "\(i + 1)", selected: state.tool == .place(k), action: { state.tool = .place(k) }) {
                        SymbolIcon(kind: k).frame(width: 50, height: 24)
                    }
                }
                Divider().padding(.vertical, 2)
                ToolButton(title: "Borrar", key: "D", selected: state.tool == .delete, action: { state.tool = .delete }) {
                    Image(systemName: "eraser").font(.system(size: 18))
                }
            }
            .padding(8)
        }
    }
}

struct ToolButton<Icon: View>: View {
    let title: String
    let key: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon().frame(height: 24)
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 68, height: 50)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.2) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) (\(key))")
    }
}

struct StatusBar: View {
    var state: AppState

    private var hint: String {
        switch state.tool {
        case .select: "Arrastra para mover · arrastra desde un borne para tender un cable · doble clic en un interruptor para abrirlo/cerrarlo · R gira · ⌫ borra"
        case .wire: "Arrastra de un punto a otro para tender un cable · Esc para terminar"
        case .delete: "Haz clic sobre un componente o cable para borrarlo · Esc para terminar"
        case .place(let k): "Haz clic para colocar \(k.withArticle) · R gira · Esc para terminar"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(hint).lineLimit(1).truncationMode(.tail)
            Spacer()
            if let h = state.hover {
                if state.result.error == nil, let v = state.result.nodeV[h] {
                    Text("Tensión del nodo: \(fmt(v, "V"))").bold().foregroundStyle(.primary)
                }
                Text("(\(h.x), \(h.y))").monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}

struct AppCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Buscar actualizaciones…") { Updater.check(userInitiated: true) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Nuevo") { state.newFile() }.keyboardShortcut("n")
            Button("Abrir…") { state.open() }.keyboardShortcut("o")
            Menu("Ejemplos") {
                Button("Circuito en serie") { state.loadExample(0) }
                Button("Circuito en paralelo") { state.loadExample(1) }
                Button("Circuito mixto") { state.loadExample(2) }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Guardar") { state.save() }.keyboardShortcut("s")
            Button("Guardar como…") { state.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Deshacer") { state.undo() }.keyboardShortcut("z")
            Button("Rehacer") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Circuito") {
            Button("Girar selección") { state.rotateSelection() }.keyboardShortcut("r")
            Button("Eliminar selección") { state.deleteSelection() }.keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Acercar") { state.zoomIn() }.keyboardShortcut("+")
            Button("Alejar") { state.zoomOut() }.keyboardShortcut("-")
            Button("Tamaño real") { state.zoom = 1 }.keyboardShortcut("0")
        }
    }
}
