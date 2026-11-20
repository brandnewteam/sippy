import AppKit
import CoreAudio
import OSLog

/// A Core Audio duck is owned by the requesting process. It attenuates other
/// playback without changing the user's volume, opening an input, or routing
/// the ringtone through a voice-processing audio unit.
@MainActor
final class IncomingCallMedia: NSObject {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var listener: AudioObjectPropertyListenerBlock?
    private var duckedDevice: AudioDeviceID?
    private var ringing = false
    private static let log = Logger(subsystem: "sm.3dprint.Sippy", category: "Call media")
    private static let pauseCommand: Int32 = 1  // MRMediaRemoteCommandPause

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(willQuit),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    func beginRinging() {
        guard !ringing else { return }
        ringing = true
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateOutput() }
        }
        if AudioObjectAddPropertyListenerBlock(system, &defaultOutput, .main, changed) == noErr {
            listener = changed
        }
        updateOutput()
    }

    func endRinging(answered: Bool = false) {
        guard ringing else { return }
        ringing = false
        if answered {
            if (Self.sendCommand?(Self.pauseCommand, nil) ?? 0) == 0 {
                Self.log.debug("The Now Playing pause command was unavailable or unhandled.")
            }
        }
        if let listener {
            AudioObjectRemovePropertyListenerBlock(system, &defaultOutput, .main, listener)
            self.listener = nil
        }
        releaseDuck()
    }

    @objc private func willQuit() { endRinging() }

    private func updateOutput() {
        guard ringing else { return } // A delivery can outlive listener removal.
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        guard AudioObjectGetPropertyData(system, &defaultOutput, 0, nil, &size, &device) == noErr,
              device != duckedDevice else { return }
        releaseDuck()
        guard device != kAudioObjectUnknown else { return }
        if Self.duck?(device, 0.25, nil, 0.20) == noErr {
            duckedDevice = device
        } else {
            Self.log.debug("The output device could not be ducked.")
        }
    }

    private func releaseDuck() {
        guard let device = duckedDevice else { return }
        if Self.duck?(device, 1, nil, 0.20) != noErr {
            Self.log.debug("The previous audio output was unavailable when releasing the duck.")
        }
        duckedDevice = nil
    }

    // macOS exports these services without public SDK declarations. Resolve
    // them independently so an unavailable service never prevents a SIP call.
    private typealias Duck = @convention(c) (AudioDeviceID, Float32, UnsafePointer<AudioTimeStamp>?, Float32) -> OSStatus
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> UInt8
    private static let duck: Duck? = load("AudioDeviceDuck", from: "/System/Library/Frameworks/CoreAudio.framework/CoreAudio")
    private static let sendCommand: SendCommand? = load("MRMediaRemoteSendCommand",
        from: "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote")

    private static func load<T>(_ symbol: String, from path: String) -> T? {
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let address = dlsym(library, symbol) else {
            dlclose(library)
            return nil
        }
        // Keep the framework loaded for the lifetime of the function pointer.
        return unsafeBitCast(address, to: T.self)
    }
}
