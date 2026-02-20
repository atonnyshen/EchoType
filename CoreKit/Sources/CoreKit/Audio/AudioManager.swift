import Foundation
import AVFoundation

// MARK: - Audio Manager
/// 麥克風管理、錄音、VAD（語音活動偵測）。
/// 跨平台：macOS + iOS 共用。
@MainActor
public final class AudioManager: ObservableObject {
    public static let shared = AudioManager()

    @Published public private(set) var isRecording = false
    @Published public private(set) var audioLevel: Float = 0
    @Published public private(set) var availableDevices: [AudioDevice] = []

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private nonisolated(unsafe) var recordingBuffer: [Float] = []
    private let bufferLock = NSLock()  // 保護 recordingBuffer 的鎖
    private var recordingCompletion: ((Data?) -> Void)?

    /// Whisper 期望的取樣率
    private let targetSampleRate: Double = 16000

    // VAD 設定
    private var silenceThreshold: Float = 0.01
    private var silenceCountdown: Int = 0
    private let silenceFrames = 30  // ~0.3 秒靜音後停止

    private init() {
        Task { await refreshDevices() }
    }

    // MARK: - Device Management

    public func refreshDevices() async {
        #if os(macOS)
        availableDevices = getMacOSAudioDevices()
        #else
        availableDevices = [AudioDevice(id: "default", name: "iPhone 麥克風", isDefault: true)]
        #endif
    }

    // MARK: - Recording

    /// 開始錄音，返回 WAV 音訊資料
    public func startRecording() async throws {
        guard !isRecording else { return }
        isRecording = true

        // 清空 buffer（使用 nonisolated 同步方法）
        clearBuffer()

        silenceCountdown = 0

        let engine = AVAudioEngine()
        audioEngine = engine
        inputNode = engine.inputNode

        let nativeFormat = engine.inputNode.outputFormat(forBus: 0)

        // 建立 16kHz mono 目標格式，用於 resample
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "無法建立 16kHz 音訊格式"])
        }

        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            if let converter {
                // Resample 到 16kHz mono
                let ratio = targetSampleRate / nativeFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status == .haveData {
                    self.processBuffer(outputBuffer)
                }
            } else {
                // Fallback: 格式相同不需轉換
                self.processBuffer(buffer)
            }
        }

        try engine.start()
    }

    /// 停止錄音，返回 WAV Data
    public func stopRecording() -> Data? {
        guard isRecording else { return nil }
        isRecording = false

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        let samples = copyBuffer()

        return encodeToWAV(samples: samples, sampleRate: Int(targetSampleRate))
    }

    // MARK: - Thread-safe buffer operations

    private nonisolated func clearBuffer() {
        bufferLock.lock()
        recordingBuffer = []
        bufferLock.unlock()
    }

    private nonisolated func copyBuffer() -> [Float] {
        bufferLock.lock()
        let copy = recordingBuffer
        bufferLock.unlock()
        return copy
    }

    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        var rms: Float = 0
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = channelData[0][i]
            samples[i] = sample
            rms += sample * sample
        }
        rms = sqrt(rms / Float(frameCount))

        // 音訊執行緒寫入 buffer，使用鎖保護
        bufferLock.lock()
        recordingBuffer.append(contentsOf: samples)
        bufferLock.unlock()

        let level = rms
        Task { @MainActor in
            self.audioLevel = level

            // H6 修復：實現 VAD 靜音檢測
            if level < self.silenceThreshold {
                self.silenceCountdown += 1
                if self.silenceCountdown >= self.silenceFrames && self.isRecording {
                    // 檢測到持續靜音，自動停止錄音
                    _ = self.stopRecording()
                }
            } else {
                self.silenceCountdown = 0
            }
        }
    }

    // MARK: - WAV Encoding

    private func encodeToWAV(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let pcmData = samples.map { Int16(max(-32768, min(32767, $0 * 32767))) }
        let dataSize = UInt32(pcmData.count * 2)

        // RIFF Header
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32LE: 36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32LE: 16)
        data.append(uint16LE: 1)              // PCM
        data.append(uint16LE: numChannels)
        data.append(uint32LE: UInt32(sampleRate))
        data.append(uint32LE: byteRate)
        data.append(uint16LE: blockAlign)
        data.append(uint16LE: bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.append(uint32LE: dataSize)
        for sample in pcmData {
            data.append(uint16LE: UInt16(bitPattern: sample))
        }
        return data
    }

    #if os(macOS)
    private func getMacOSAudioDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        var propSize: UInt32 = 0
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &propSize)
        let deviceCount = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &propSize, &deviceIds)

        for id in deviceIds {
            if let name = getDeviceName(id: id), isInputDevice(id: id) {
                devices.append(AudioDevice(id: String(id), name: name, isDefault: false))
            }
        }
        return devices
    }

    private func getDeviceName(id: AudioDeviceID) -> String? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var propSize = UInt32(MemoryLayout<CFString>.size)
        let result = AudioObjectGetPropertyData(id, &propAddress, 0, nil, &propSize, &name)
        return result == noErr ? (name as String) : nil
    }

    private func isInputDevice(id: AudioDeviceID) -> Bool {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &propAddress, 0, nil, &propSize)
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propSize))
        defer { bufferList.deallocate() }
        AudioObjectGetPropertyData(id, &propAddress, 0, nil, &propSize, bufferList)
        return bufferList.pointee.mNumberBuffers > 0
    }
    #endif
}

// MARK: - Audio Device
public struct AudioDevice: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

// MARK: - Data Helpers
private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
