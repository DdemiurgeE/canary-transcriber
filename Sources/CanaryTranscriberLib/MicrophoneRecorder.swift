import Foundation
import AVFoundation
import AudioToolbox
import CanaryTranscriberCore

final class MicrophoneEngineRecorder {
    let url: URL
    private let deviceUID: String?
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var recordedFrames: AVAudioFramePosition = 0

    init(url: URL, deviceUID: String?) {
        self.url = url
        self.deviceUID = deviceUID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? deviceUID : nil
    }

    func start() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let input = engine.inputNode
        if let deviceUID, let audioDeviceID = Self.audioDeviceID(matchingUID: deviceUID), let audioUnit = input.audioUnit {
            var mutableDeviceID = audioDeviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 21, userInfo: [NSLocalizedDescriptionKey: "Could not select microphone \(deviceUID) for AVAudioEngine (AudioUnitSetProperty status \(status))."])
            }
        } else if let deviceUID {
            throw NSError(domain: "CanaryAppAudioCapture", code: 23, userInfo: [NSLocalizedDescriptionKey: "Could not find the CoreAudio device for microphone \(deviceUID). Select System default microphone or click Refresh mics."])
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "CanaryAppAudioCapture", code: 22, userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine returned an empty input format for the microphone."])
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.file = file
        recordedFrames = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, buffer.frameLength > 0 else { return }
            do {
                try self.file?.write(from: buffer)
                self.recordedFrames += AVAudioFramePosition(buffer.frameLength)
            } catch {
                // Surface this on finish via the tiny-file/empty-file validation.
            }
        }
        engine.prepare()
        try engine.start()
    }

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil

        if CaptureFileValidator.isUsableAudioFile(url), recordedFrames >= CaptureFileValidator.minimumMicrophoneFrames {
            completion(.success(url))
        } else {
            completion(.failure(NSError(domain: "CanaryAppAudioCapture", code: 18, userInfo: [NSLocalizedDescriptionKey: CaptureDiagnostic.emptyOrTinyFile(url).description])))
        }
    }

    static func audioDeviceID(matchingUID targetUID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else { return nil }

        for device in devices {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var uid: Unmanaged<CFString>?
            if AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr,
               uid?.takeUnretainedValue() as String? == targetUID {
                return device
            }
        }
        return nil
    }
}
