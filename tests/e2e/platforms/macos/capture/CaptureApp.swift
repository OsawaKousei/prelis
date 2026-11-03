import AppKit
import Foundation
import ScreenCaptureKit

@MainActor
final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await execute(); NSApplication.shared.terminate(nil) }
    }

    private func execute() async {
        guard CommandLine.arguments.count == 2 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let stateURL = directory.appendingPathComponent("state.json")
        func state(_ value: [String: Any]) {
            try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]).write(to: stateURL, options: .atomic)
        }
        do {
            guard CGPreflightScreenCaptureAccess() else {
                state(["status": "permission-required", "pid": ProcessInfo.processInfo.processIdentifier,
                       "error": "Allow Prelis E2E Capture in System Settings > Privacy & Security > Screen & System Audio Recording, then rerun."])
                _ = CGRequestScreenCaptureAccess()
                return
            }
            let data = try Data(contentsOf: directory.appendingPathComponent("job.json"))
            let job = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let recorder = WindowRecorder(directory: directory, bundleID: job["bundle_id"] as! String,
                                          appURL: URL(fileURLWithPath: job["app_path"] as! String),
                                          mergeVideo: job["record"] as! Bool)
            try recorder.state()
            let deadline = Date().addingTimeInterval(900)
            while Date() < deadline {
                if kill(job["owner_pid"] as! Int32, 0) != 0 { break }
                let requests = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("requests"), includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                for requestURL in requests where requestURL.pathExtension == "json" {
                    let request = try JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as! [String: Any]
                    let response = directory.appendingPathComponent("responses/\(requestURL.lastPathComponent)")
                    if FileManager.default.fileExists(atPath: response.path) { continue }
                    do {
                        var value: [String: Any] = [:]
                        switch request["command"] as? String {
                        case "start": try await recorder.start(name: request["name"] as! String, pid: request["pid"] as! Int32)
                        case "stop": value = try await recorder.stop()
                        case "mark": value["time"] = try recorder.mark(request["name"] as! String)
                        case "finish": value = try await recorder.finish()
                        default: throw CaptureFailure.message("Unknown capture command")
                        }
                        try recorder.write(["status": "ok", "data": value], to: response)
                        if request["command"] as? String == "finish" { return }
                    } catch {
                        try recorder.write(["status": "error", "error": String(describing: error)], to: response)
                    }
                }
                try recorder.state()
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            _ = try await recorder.stop()
            state(["status": "stopped"])
        } catch {
            state(["status": "error", "error": String(describing: error)])
        }
    }
}

@main
struct CaptureApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CaptureAppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
