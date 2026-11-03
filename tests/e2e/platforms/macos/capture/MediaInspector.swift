import AVFoundation
import Foundation

enum CaptureFailure: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let text) = self { return text }; return "Capture failed" }
}

enum MediaInspector {
    static func inspect(_ url: URL, pcmURL: URL?) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let track = video.first else { throw CaptureFailure.message("No recorded video track") }
        let size = try await track.load(.naturalSize)
        var result: [String: Any] = ["duration_seconds": duration, "width": size.width, "height": size.height,
                                      "video_tracks": video.count, "audio_tracks": audio.count]
        if let pcmURL, let audioTrack = audio.first {
            try decodeAudio(asset: asset, track: audioTrack, destination: pcmURL, duration: duration)
            result["pcm_file"] = pcmURL.lastPathComponent
        }
        return result
    }

    private static func decodeAudio(asset: AVAsset, track: AVAssetTrack, destination: URL, duration: Double) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CaptureFailure.message("Cannot decode captured audio") }
        var pcm = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard start.isFinite, start >= -0.1, start <= duration + 1 else {
                throw CaptureFailure.message("Captured audio timestamps are outside the video timeline")
            }
            let offset = max(0, Int((start * 16000).rounded())) * 2
            let count = CMBlockBufferGetDataLength(buffer)
            var bytes = Data(count: count)
            let status = bytes.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: count, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw CaptureFailure.message("Cannot read audio PCM samples") }
            if pcm.count < offset { pcm.append(Data(count: offset - pcm.count)) }
            if offset >= pcm.count { pcm.append(bytes) }
            else {
                let overlap = pcm.count - offset
                if overlap < bytes.count { pcm.append(bytes.dropFirst(overlap)) }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? CaptureFailure.message("Audio decoding failed") }
        var header = Data()
        func ascii(_ text: String) { header.append(text.data(using: .ascii)!) }
        func u32(_ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { header.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var n = value.littleEndian; withUnsafeBytes(of: &n) { header.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + pcm.count)); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16); ascii("data"); u32(UInt32(pcm.count))
        header.append(pcm)
        try header.write(to: destination, options: .atomic)
    }

    static func merge(_ urls: [URL], to destination: URL) async throws -> [String: Any] {
        guard !urls.isEmpty else { throw CaptureFailure.message("No window recordings were produced") }
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        var cursor = CMTime.zero
        var expectedSize: CGSize?
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw CaptureFailure.message("A window segment has no video")
            }
            let size = try await source.load(.naturalSize)
            if let expectedSize, expectedSize != size { throw CaptureFailure.message("Window dimensions changed between segments") }
            expectedSize = size
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                let range = try await sound.load(.timeRange)
                try audio.insertTimeRange(range, of: sound, at: cursor + range.start)
            }
            cursor = cursor + duration
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CaptureFailure.message("Cannot create the window video exporter")
        }
        try await exporter.export(to: destination, as: .mp4)
        return try await inspect(destination, pcmURL: nil)
    }
}
