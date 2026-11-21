import AVFoundation
import Foundation
import Observation
import linphone

/// Ringtones from the Linphone framework, the app bundle and user imports in
/// `~/Library/Application Support/Sippy/Ringtones`.
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
        var linphoneTitle: String?
        var id: String { url.path }
        var fileName: String { url.lastPathComponent }
        // Keep existing filename preferences, including imports that happen
        // to have the same filename as one of the new SDK choices.
        var selectionKey: String { linphoneTitle == nil ? fileName : "linphone/" + fileName }
        var displayName: String {
            if let linphoneTitle { return linphoneTitle }
            if isBuiltIn, fileName == "Time not Lost.wav" { return "Time Not Lost" }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    private(set) var ringtones: [Ringtone] = []

    static let importableExtensions = ["wav", "caf", "mp3", "m4a", "aif", "aiff"]

    private var previewPlayer: AVAudioPlayer?
    private var linphonePreview: LinphoneRingPreview?
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
        // The first available SDK tone is the default. Read from the loaded
        // framework so both a packaged app and a SwiftPM build use one copy.
        if let resources = Bundle(identifier: "org.linphone.linphone") {
            for (file, title) in [("notes_of_the_optimistic.mkv", "Notes of the Optimistic"),
                                  ("oldphone-mono.wav", "Old Phone")] {
                if let url = resources.url(forResource: file, withExtension: nil),
                   FileManager.default.isReadableFile(atPath: url.path) {
                    found.append(Ringtone(url: url, isBuiltIn: true, linphoneTitle: title))
                }
            }
        }
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

    /// A new account or a retired ringtone resolves to Notes, then Old Phone.
    func ringtone(named key: String?) -> Ringtone? {
        if let key, let match = ringtones.first(where: { $0.selectionKey == key }) {
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
        if ringtone.url.pathExtension == "mkv" {
            linphonePreview = LinphoneRingPreview(url: ringtone.url) { [weak self] in self?.stopPreview() }
            if linphonePreview != nil { previewingID = ringtone.id }
            return
        }
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
        linphonePreview = nil
        previewPlayer?.stop()
        previewPlayer = nil
        previewingID = nil
    }
}

/// Plays the SDK's Matroska ringtone without starting a SIP core. The
/// media factory and audio output live only for the duration of the preview.
private final class LinphoneRingPreview {
    private let factory = ms_factory_new_with_voip()
    private let player = linphone_ringtoneplayer_new()
    private let finished: DispatchWorkItem

    init?(url: URL, onFinish: @escaping () -> Void) {
        finished = DispatchWorkItem(block: onFinish)
        guard let card = ms_snd_card_manager_get_default_playback_card(ms_factory_get_snd_card_manager(factory))
        else { return nil }
        let cards = bctbx_list_append(nil, card)
        defer { bctbx_list_free(cards) }
        let result = linphone_ringtoneplayer_start_with_cb(factory, player, cards, url.path, -1, { _, context, _ in
            guard let context else { return }
            let finished = Unmanaged<DispatchWorkItem>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async(execute: finished)
        }, Unmanaged.passUnretained(finished).toOpaque())
        guard result == 0 else { return nil }
    }

    deinit {
        finished.cancel()
        linphone_ringtoneplayer_destroy(player)
        ms_factory_destroy(factory)
    }
}
