import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class WindowRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    let directory: URL
    let bundleID: String
    let appURL: URL
    let mergeVideo: Bool
    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var started = false
    private var finished = false
    private var failure: String?
    private var beganAt: TimeInterval = 0
    private var active: [String: Any]?
    private(set) var segments: [[String: Any]] = []

    init(directory: URL, bundleID: String, appURL: URL, mergeVideo: Bool) {
        self.directory = directory; self.bundleID = bundleID; self.appURL = appURL; self.mergeVideo = mergeVideo
    }

    func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    func state() throws {
        var value: [String: Any] = ["status": stream == nil ? "ready" : "capturing", "pid": ProcessInfo.processInfo.processIdentifier]
        if let active {
            value["segment"] = active["name"]
            value["elapsed"] = max(0, ProcessInfo.processInfo.systemUptime - beganAt)
        }
        if let failure { value["status"] = "error"; value["error"] = failure }
        try write(value, to: directory.appendingPathComponent("state.json"))
    }

    func start(name: String, pid: pid_t) async throws {
        guard stream == nil else { throw CaptureFailure.message("A recording is already active") }
        guard name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw CaptureFailure.message("Invalid segment name") }
        guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == bundleID,
              app.bundleURL?.resolvingSymlinksInPath() == appURL.resolvingSymlinksInPath() else {
            throw CaptureFailure.message("The requested process is not the selected app")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.title == "Prelis" && $0.windowLayer == 0 }
        guard windows.count == 1, let window = windows.first else { throw CaptureFailure.message("Expected one Prelis window owned by the selected process") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale)) / 2 * 2
        config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale)) / 2 * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = false
        let filename = String(format: "%02d-%@.mp4", segments.count + 1, name)
        let destination = directory.appendingPathComponent(filename)
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = destination
        outputConfig.videoCodecType = .h264
        outputConfig.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        try capture.addRecordingOutput(output)
        started = false; finished = false; failure = nil
        active = ["name": name, "file": filename, "window_id": window.windowID, "pid": pid,
                  "bundle_id": bundleID, "width": config.width, "height": config.height,
                  "filter": "desktop-independent-window", "markers": [String: Double]()]
        stream = capture; recording = output
        beganAt = ProcessInfo.processInfo.systemUptime
        try await capture.startCapture()
        try await until("Recording did not start") { self.started }
        try state()
    }

    func mark(_ name: String) throws -> Double {
        guard active != nil else { throw CaptureFailure.message("No active window recording") }
        let time = ProcessInfo.processInfo.systemUptime - beganAt
        var markers = active!["markers"] as! [String: Double]
        markers[name] = time; active!["markers"] = markers
        return time
    }

    func stop() async throws -> [String: Any] {
        guard let capture = stream, var segment = active else { return [:] }
        try await capture.stopCapture()
        try await until("Recording did not finish") { self.finished }
        stream = nil; recording = nil; active = nil
        let url = directory.appendingPathComponent(segment["file"] as! String)
        let pcm = url.deletingPathExtension().appendingPathExtension("wav")
        segment["media"] = try await MediaInspector.inspect(url, pcmURL: pcm)
        segments.append(segment)
        try write(["segments": segments], to: directory.appendingPathComponent("report.json"))
        try state()
        return segment
    }

    func finish() async throws -> [String: Any] {
        _ = try await stop()
        var report: [String: Any] = ["segments": segments, "scope": "selected-app-window", "microphone": false]
        if mergeVideo {
            let urls = segments.map { directory.appendingPathComponent($0["file"] as! String) }
            report["media"] = try await MediaInspector.merge(urls, to: directory.deletingLastPathComponent().appendingPathComponent("recording.mp4"))
        }
        try write(report, to: directory.appendingPathComponent("report.json"))
        return report
    }

    private func until(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(25)
        while !condition() {
            if let failure { throw CaptureFailure.message(failure) }
            guard Date() < deadline else { throw CaptureFailure.message(message) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.started = true }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finished = true }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.failure = error.localizedDescription }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.failure = error.localizedDescription }
    }
}
