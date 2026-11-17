import AVFoundation
import Foundation
import Observation

/// The ringtones Sippy can ring with: the bundled set (app Resources, with a
/// repo fallback for `swift run`) plus user-imported files in
/// `~/Library/Application Support/Sippy/Ringtones`.
///
/// The bundled set is third-party work under CC0 / CC BY (see
/// `Support/Ringtones/CREDITS.md`, written by `Tools/fetch_ringtones.py`
/// together with the `credits.json` read here).
@MainActor
@Observable
final class RingtoneLibrary {
    /// Author and license of a bundled ringtone, from `credits.json`.
    struct Credit: Equatable, Decodable {
        let file: String
        let author: String
        let licenseName: String

        /// nil for anonymous work: there is no name to show.
        var displayAuthor: String? { author == "Anonymous" ? nil : author }

        var summary: String {
            displayAuthor.map { "By \($0), \(licenseName)" } ?? licenseName
        }
    }

    struct Ringtone: Identifiable, Equatable {
        let url: URL
        let isBuiltIn: Bool
        var credit: Credit?
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
            let credits = Self.credits(in: builtIn)
            found += list(directory: builtIn, builtIn: true).map { tone in
                var tone = tone
                tone.credit = credits[tone.fileName]
                return tone
            }
        }
        found += list(directory: Self.userDirectory, builtIn: false)
        ringtones = found
    }

    /// Credits by filename; empty when the file is missing or unreadable
    /// (the ringtones still work, they just show no author).
    private static func credits(in directory: URL) -> [String: Credit] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("credits.json")),
              let credits = try? JSONDecoder().decode([Credit].self, from: data)
        else { return [:] }
        return Dictionary(credits.map { ($0.file, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func list(directory: URL, builtIn: Bool) -> [Ringtone] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { Self.importableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                    == .orderedAscending
            }
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
        // A short ring pattern plays twice so the loop can be judged; a
        // tune of its own length plays once.
        let plays: Double = player.duration < 12 ? 2 : 1
        player.numberOfLoops = Int(plays) - 1
        player.play()
        previewPlayer = player
        previewingID = ringtone.id
        // Clear the state when the (finite) preview runs out.
        let id = ringtone.id
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration * plays + 0.1) { [weak self] in
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
