/// Names for the audio device pickers. The SIP stack names a device after
/// macOS's device name plus its UID in parentheses ("MacBook Pro Speakers
/// (BuiltInSpeakerDevice)", "M28U (1C540028-…)"), and calls the device that
/// follows the system setting "Default Capture" / "Default Playback".
public enum AudioDeviceNames {
    public static let systemDefault = "System Default"

    /// Display names, in the order given. The UID suffix is dropped unless
    /// that would leave two devices in the list with the same name.
    public static func displayNames(for names: [String]) -> [String] {
        let short = names.map(shortName)
        return zip(names, short).map { full, name in
            short.filter { $0 == name }.count > 1 ? full : name
        }
    }

    static func shortName(_ name: String) -> String {
        if name == "Default Capture" || name == "Default Playback" { return systemDefault }
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else {
            return name
        }
        let base = String(name[..<open.lowerBound])
        return base.isEmpty ? name : base
    }
}
