import CoreAudio

enum AudioVolume {
    static func elements(main: Bool, preferred: [UInt32], has: (UInt32) -> Bool) -> [UInt32] {
        if main { return [0] }
        var seen = Set<UInt32>()
        return (preferred.isEmpty ? [1, 2] : preferred).filter { $0 > 0 && seen.insert($0).inserted && has($0) }
    }
    static func address(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
    static func addresses(_ device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var main = address(0)
        var stereo = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo, mScope: kAudioDevicePropertyScopeOutput, mElement: 0)
        var channels: [UInt32] = [0, 0]
        var size = UInt32(2 * MemoryLayout<UInt32>.size)
        let status = channels.withUnsafeMutableBytes { AudioObjectGetPropertyData(device, &stereo, 0, nil, &size, $0.baseAddress!) }
        return elements(main: AudioObjectHasProperty(device, &main), preferred: status == noErr && size == 8 ? channels : []) { element in
            var value = address(element)
            return AudioObjectHasProperty(device, &value)
        }.map(address)
    }
    static func read(_ device: AudioDeviceID) -> (value: Double?, writable: Bool) {
        let properties = addresses(device)
        guard !properties.isEmpty else { return (nil, false) }
        var values: [Double] = [], writable = true
        for var property in properties {
            var value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr,
                  value.isFinite, (0...1).contains(value) else { return (nil, false) }
            values.append(Double(value))
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device, &property, &settable) != noErr || !settable.boolValue { writable = false }
        }
        return (values.max(), writable)
    }
    static func set(_ value: Double, device: AudioDeviceID) -> Bool {
        guard value.isFinite, (0...1).contains(value), read(device).writable else { return false }
        let properties = addresses(device)
        guard !properties.isEmpty else { return false }
        var succeeded = true
        for var property in properties {
            var scalar = Float32(value)
            if AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) != noErr { succeeded = false }
        }
        return succeeded
    }
}
