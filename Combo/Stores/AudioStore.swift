import AppKit
import Combine
import CoreAudio

struct OutputChoice: Identifiable {
    let id: AudioDeviceID
    let name: String
    var symbol: String = "speaker.wave.2"
}

@MainActor final class AudioStore: ObservableObject {
    @Published var volume: Double?
    @Published var muted = false
    @Published var output = ""
    @Published var outputIsAirPods = false
    @Published var outputDevices: [OutputChoice] = []
    @Published var canVolume = false
    @Published var canMute = false
    @Published var message = "" { didSet { onMessage?(message) } }
    let airpods = AirPodsControl()
    let bluetoothPermission = BluetoothPermission()
    var onUpdate: (() -> Void)?
    var onVolumeChange: (() -> Void)?
    var onAudioReset: ((Bool) -> Void)?
    var onMessage: ((String) -> Void)?
    private var device: AudioDeviceID = 0
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private(set) var listenersAvailable = false
    var selectedOutputID: AudioDeviceID { device }
    func refreshAudio() {
        let oldVolume = volume
        let oldMuted = muted
        let oldDevice = device
        var id: AudioDeviceID = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else {
            volume = nil; muted = false; output = "输出设备不可用"; canVolume = false; canMute = false
            outputIsAirPods = false
            device = 0; installAudioListeners(); onUpdate?(); onAudioReset?(oldDevice != 0); return
        }
        device = id
        if oldDevice != id || audioListeners.isEmpty { installAudioListeners(); onAudioReset?(oldDevice != id) }
        output = "未知输出设备"
        a = address(kAudioObjectPropertyName, global: true)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr { output = name?.takeRetainedValue() as String? ?? "未知输出设备" }
        var transport: UInt32 = 0
        a = address(kAudioDevicePropertyTransportType, global: true); size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &transport)
        // ponytail: reuse the output list's name heuristic; use model identity for renamed AirPods.
        outputIsAirPods = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport)
            && output.localizedCaseInsensitiveContains("AirPods")
        let reading = AudioVolume.read(id)
        volume = reading.value
        canVolume = reading.writable
        var settable = DarwinBoolean(false)
        var mute: UInt32 = 0
        a = address(kAudioDevicePropertyMute); size = UInt32(MemoryLayout<UInt32>.size)
        let muteRead = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &mute) == noErr
        muted = muteRead && mute != 0
        canMute = muteRead && AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        onUpdate?()
        let volumeChanged = oldVolume.flatMap { previous in volume.map { abs(previous-$0) > 0.001 } } ?? false
        if oldDevice == id, volumeChanged || (muteRead && oldMuted != muted) { onVolumeChange?() }

    }
    func address(_ selector: AudioObjectPropertySelector, global: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: global ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    func refreshOutputs() {
        var a = address(kAudioHardwarePropertyDevices, global: true)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { outputDevices = []; return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard ids.withUnsafeMutableBytes({ AudioObjectGetPropertyData(system, &a, 0, nil, &size, $0.baseAddress!) }) == noErr else { outputDevices = []; return }
        outputDevices = ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = address(kAudioObjectPropertyName, global: true)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let title = name?.takeRetainedValue() as String? else { return nil }
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = address(kAudioDevicePropertyTransportType, global: true)
            _ = AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            let symbol: String
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: symbol = "laptopcomputer"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: symbol = "display"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                symbol = title.localizedCaseInsensitiveContains("AirPods") ? "airpodspro" : "headphones"
            case kAudioDeviceTransportTypeAirPlay: symbol = "airplay.audio"
            default: symbol = "speaker.wave.2"
            }
            return OutputChoice(id: id, name: title, symbol: symbol)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func setOutput(_ id: AudioDeviceID) {
        refreshOutputs()
        guard outputDevices.contains(where: { $0.id == id }) else { message = "输出设备已不可用，请重试。"; return }
        var selected = id
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, global: true)
        message = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout.size(ofValue: selected)), &selected) == noErr ? "" : "无法切换输出设备。"
        refreshAudio()
    }
    func installAudioListeners() {
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
        var targets: [(AudioObjectID, AudioObjectPropertyAddress)] = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map { (AudioObjectID(kAudioObjectSystemObject), address($0, global: true)) }
        if device != 0 {
            targets += AudioVolume.addresses(device).map { (device, $0) }
            targets += [kAudioDevicePropertyMute, kAudioDevicePropertyStreams].map { (device, address($0)) }
            targets.append((device, address(kAudioObjectPropertyName, global: true)))
        }
        var failed = false
        for (id, var attr) in targets where AudioObjectHasProperty(id, &attr) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.refreshAudio(); self?.refreshOutputs() } }
            if AudioObjectAddPropertyListenerBlock(id, &attr, .main, block) == noErr { audioListeners.append((id,attr,block)) } else { failed = true }
        }
        listenersAvailable = !failed
    }
    func setVolume(_ value: Double, isLive: Bool) {
        guard isLive, value.isFinite, (0...1).contains(value) else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canVolume else { message = "输出设备已变化或不支持音量控制，请重试。"; return }
        let adjusted = AudioVolume.set(value, device: device)
        message = adjusted ? "" : "未能调节全部声道，请重试。"
        if adjusted && value > 0 && muted {
            if canMute {
                var mute: UInt32 = 0; var a = address(kAudioDevicePropertyMute)
                if AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: mute)), &mute) != noErr {
                    message = "音量已调整，但当前设备无法取消静音。"
                }
            } else { message = "音量已调整，但当前设备不支持取消静音。" }
        }
        refreshAudio()
    }
    func toggleMute(isLive: Bool) {
        guard isLive else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canMute else { message = "输出设备已变化或不支持静音，请重试。"; return }
        var v: UInt32 = muted ? 0 : 1; var a = address(kAudioDevicePropertyMute)
        message = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr ? "" : "当前设备无法切换静音。"
        refreshAudio()
    }
    func stop() {
        airpods.cancel()
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
    }
}
