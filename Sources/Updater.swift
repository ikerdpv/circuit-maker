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

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let assets: [Asset]
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
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 { throw UpdateError("Todavía no hay ninguna versión publicada.") }
                guard status == 200 else { throw UpdateError("GitHub respondió con el error \(status).") }

                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard isNewer(latest, than: currentVersion),
                      let asset = release.assets.first(where: { $0.name == assetName }) else {
                    if userInitiated {
                        info("Circuit Maker está al día", "Tienes la última versión (\(currentVersion)).")
                    }
                    return
                }

                let auto = ProcessInfo.processInfo.environment["CIRCUITMAKER_AUTOUPDATE"] == "1"
                if !auto {
                    let alert = NSAlert()
                    alert.messageText = "Hay una versión nueva de Circuit Maker (\(latest))"
                    var text = "Tienes la \(currentVersion). Se descargará e instalará sola, y la app se reiniciará."
                    if let notes = release.body, !notes.isEmpty { text += "\n\nNovedades:\n\(notes.prefix(800))" }
                    alert.informativeText = text
                    alert.addButton(withTitle: "Actualizar ahora")
                    alert.addButton(withTitle: "Más tarde")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                try await install(from: asset.browser_download_url)
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
