import AVFoundation
import CoreAudio

nonisolated struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// CoreAudio device UID - stable across reboots and reconnects.
    let uid: String
    let name: String

    var id: String { uid }
}

nonisolated enum AudioInputDevices {
    static func all() -> [AudioInputDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                         mediaType: .audio, position: .unspecified)
            .devices
            .map { AudioInputDevice(uid: $0.uniqueID, name: $0.localizedName) }
    }

    /// AVCaptureDevice's uniqueID is the CoreAudio UID on macOS; AVAudioEngine
    /// needs the numeric device ID that UID maps to right now.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), qualifier,
                                       &size, &deviceID)
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
