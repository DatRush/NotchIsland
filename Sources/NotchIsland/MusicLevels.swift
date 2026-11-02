import AppKit
import os
import ScreenCaptureKit

// One instance per visible waveform. Only the selected application's audio is requested.
final class MusicLevels: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    private let logger = Logger(subsystem: "NotchIsland", category: "MusicLevels")
    private let lock = NSLock()
    private var bands = Array(repeating: 0.0, count: 5)
    private var updated = -Double.infinity

    func snapshot(at now: Double) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        return now - updated < 0.5 ? bands : nil
    }

    @Published private(set) var capturing = false
    @MainActor private weak var currentStream: SCStream?

    @MainActor private func ended(_ stream: SCStream) {
        guard currentStream === stream else { return }
        currentStream = nil
        capturing = false
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.ended(stream) }
    }

    @MainActor func observe(source: String) async {
        guard CGPreflightScreenCaptureAccess() else {
            logger.notice("System audio capture permission unavailable")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let app = content.applications.first(where: { $0.bundleIdentifier == source }),
                  let display = content.displays.first, !Task.isCancelled else { return }
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.channelCount = 1
            config.sampleRate = 48000
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "NotchIsland.musicLevels"))
            currentStream = stream
            capturing = false
            defer { ended(stream) }
            try await stream.startCapture()
            if currentStream === stream && !Task.isCancelled { capturing = true }
            while currentStream === stream && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            try? await stream.stopCapture()
        } catch { return }
    }

    private static let coefficients = [120.0, 450, 1700, 6000].map { 1 - exp(-2 * Double.pi * $0 / 48000) }
    private var recentPeaks = Array(repeating: 0.012, count: 5)
    private var lowPass = Array(repeating: 0.0, count: 4)

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let description = buffer.formatDescription,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mChannelsPerFrame == 1, format.mBitsPerChannel == 32,
              let block = buffer.dataBuffer else { return }
        let count = buffer.numSamples
        guard count > 0, count <= 48000, CMBlockBufferGetDataLength(block) == count * 4 else { return }
        var samples = [Float](repeating: 0, count: count)
        let status = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        guard status == noErr else { return }
        var energy = Array(repeating: 0.0, count: 5)
        for value in samples {
            let input = Double(value)
            var previous = 0.0
            for band in lowPass.indices {
                lowPass[band] += Self.coefficients[band] * (input - lowPass[band])
                let signal = lowPass[band] - previous
                energy[band] += signal * signal
                previous = lowPass[band]
            }
            energy[4] += (input - previous) * (input - previous)
        }
        lock.lock()
        let interval = Double(count) / 48000
        let peakDecay = exp(-interval / 2.5)
        for band in bands.indices {
            let rms = sqrt(energy[band] / Double(count))
            // Follow each band's recent loud passages so a beat has room to move
            // on quiet recordings as well as heavily compressed tracks.
            recentPeaks[band] = max(0.012, rms, recentPeaks[band] * peakDecay)
            let relative = max(0, (rms - 0.001) / recentPeaks[band])
            let target = min(1, relative * relative)
            let seconds = target > bands[band] ? 0.012 : 0.085
            bands[band] += (target - bands[band]) * (1 - exp(-interval / seconds))
        }
        if updated == -Double.infinity { logger.notice("Received player audio samples") }
        updated = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }
}
