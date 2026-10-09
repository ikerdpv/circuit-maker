import AppKit

/// Busca versiones nuevas en GitHub Releases y se actualiza sola.
@MainActor
enum Updater {
    static let repo = "ikerdpv/circuit-maker"
    static let assetName = "Circuit-Maker-macOS.zip"

    private static var busy = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// `userInitiated`: si es false (al arrancar) no se muestra nada cuando no hay novedades o falla la red.
    static func check(userInitiated: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                // github.com/<repo>/releases/latest redirige a .../releases/tag/vX.Y.Z.
                // Se usa en lugar de la API porque la API limita a 60 consultas por hora por IP.
                var req = URLRequest(url: URL(string: "https://github.com/\(repo)/releases/latest")!)
                req.httpMethod = "HEAD"
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let finalURL = http.url else {
                    throw UpdateError("No se pudo conectar con GitHub.")
                }
                let tag = finalURL.lastPathComponent
                guard finalURL.pathComponents.contains("tag"), tag.lowercased().hasPrefix("v") else {
                    throw UpdateError("Todavía no hay ninguna versión publicada.")
                }
                let latest = String(tag.dropFirst())
                guard isNewer(latest, than: currentVersion) else {
                    if userInitiated {
                        info("Circuit Maker está al día", "Tienes la última versión (\(currentVersion)).")
                    }
                    return
                }
                let download = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(assetName)")!

                let auto = ProcessInfo.processInfo.environment["CIRCUITMAKER_AUTOUPDATE"] == "1"
                if !auto {
                    let alert = NSAlert()
                    alert.messageText = "Hay una versión nueva de Circuit Maker (\(latest))"
                    alert.informativeText = "Tienes la \(currentVersion). Se descargará e instalará sola, y la app se reiniciará."
                    alert.addButton(withTitle: "Actualizar ahora")
                    alert.addButton(withTitle: "Más tarde")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                try await install(from: download)
            } catch {
                if userInitiated {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "No se pudo actualizar"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    /// "1.2.10" > "1.2.9"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func install(from url: URL) async throws {
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else { throw UpdateError("La app no se está ejecutando desde un paquete .app.") }
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError("No tengo permiso para escribir en \(target.deletingLastPathComponent().path).")
        }

        NSApp.dockTile.badgeLabel = "↓"
        defer { NSApp.dockTile.badgeLabel = nil }

        let (downloaded, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("No se pudo descargar la actualización.") }

        let work = fm.temporaryDirectory.appendingPathComponent("CircuitMakerUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: downloaded, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0,
              let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("El archivo descargado no contiene la app.")
        }

        // Espera a que esta app se cierre, cambia el paquete y abre la nueva versión.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3"
        mv "$2" "$3"
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        open "$3"
        rm -rf "$4"
        """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/bash")
        swap.arguments = ["-c", script, "updater", String(ProcessInfo.processInfo.processIdentifier),
                          newApp.path, target.path, work.path]
        try swap.run()
        NSApp.terminate(nil)
    }

    private static func info(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
