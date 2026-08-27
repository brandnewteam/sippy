import AVFoundation
import Foundation
import Observation

/// The ringtones Sippy can ring with: the bundled set (app Resources, with a
/// repo fallback for `swift run`) plus user-imported files in
/// `~/Library/Application Support/Sippy/Ringtones`.
@MainActor
@Observable
final class RingtoneLibrary {
    struct Ringtone: Identifiable, Equatable {
        let url: URL
        let isBuiltIn: Bool
        var id: String { url.path }
        /// Filename including extension — the stable key stored in the
        /// account config (so the library can move without invalidating it).
        var fileName: String { url.lastPathComponent }
        var displayName: String { url.deletingPathExtension().lastPathComponent }
    }

    private(set) var ringtones: [Ringtone] = []

    static let importableExtensions = ["wav", "caf", "mp3", "m4a", "aif", "aiff"]

    private var previewPlayer: AVAudioPlayer?
    private(set) var previewingID: String?

    static var userDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sippy/Ringtones", isDirectory: true)
    }

    private static var builtInDirectory: URL? {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("Ringtones", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        // Bare executable (swift run): use the repo's copy.
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Support/Ringtones", isDirectory: true)
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    init() {
        reload()
    }

    func reload() {
        var found: [Ringtone] = []
        if let builtIn = Self.builtInDirectory {
            found += list(directory: builtIn, builtIn: true)
        }
        found += list(directory: Self.userDirectory, builtIn: false)
        ringtones = found
    }

    private func list(directory: URL, builtIn: Bool) -> [Ringtone] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { Self.importableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { Ringtone(url: $0, isBuiltIn: builtIn) }
    }

    /// nil filename (or a vanished file) falls back to the first bundled tone.
    func ringtone(named fileName: String?) -> Ringtone? {
        if let fileName, let match = ringtones.first(where: { $0.fileName == fileName }) {
            return match
        }
        return ringtones.first(where: \.isBuiltIn) ?? ringtones.first
    }

    @discardableResult
    func importRingtone(from source: URL) throws -> Ringtone {
        let directory = Self.userDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        // Never overwrite: "Ring.wav" → "Ring 2.wav" …
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            destination = directory.appendingPathComponent(
                "\(base) \(counter).\(source.pathExtension)")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        reload()
        return Ringtone(url: destination, isBuiltIn: false)
    }

    /// Only user-imported ringtones can be deleted.
    func delete(_ ringtone: Ringtone) {
        guard !ringtone.isBuiltIn else { return }
        try? FileManager.default.removeItem(at: ringtone.url)
        reload()
    }

    // MARK: - Preview

    func togglePreview(_ ringtone: Ringtone) {
        if previewingID == ringtone.id {
            stopPreview()
            return
        }
        stopPreview()
        guard let player = try? AVAudioPlayer(contentsOf: ringtone.url) else { return }
        player.numberOfLoops = 1
        player.play()
        previewPlayer = player
        previewingID = ringtone.id
        // Clear the state when the (finite) preview runs out.
        let id = ringtone.id
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration * 2 + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.previewingID == id, self.previewPlayer?.isPlaying != true
                else { return }
                self.stopPreview()
            }
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingID = nil
    }
}
