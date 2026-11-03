import Foundation

final class MacCaptureClient {
    private let url: URL
    private let token: String
    private unowned let driver: MacAppDriver
    private(set) var active = false

    init?(driver: MacAppDriver) {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["PRELIS_E2E_CAPTURE_URL"], let url = URL(string: address),
              let token = environment["PRELIS_E2E_CAPTURE_TOKEN"] else { return nil }
        self.url = url; self.token = token; self.driver = driver
    }

    private func request(_ value: [String: Any]?) throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        if let value {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: value)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var requestError: Error?
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data; requestError = error; semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 46) == .success else {
            task.cancel(); throw E2EError.condition("Window capture command timed out")
        }
        if let requestError { throw requestError }
        guard let responseData,
              let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw E2EError.condition("The window capture service returned no response")
        }
        guard response["status"] as? String != "error" else {
            throw E2EError.condition("Window capture failed: \(response["error"] ?? "unknown error")")
        }
        return value == nil ? response : response["data"] as? [String: Any] ?? [:]
    }

    func start(name: String, pid: pid_t) throws {
        if active { try stop() }
        _ = try request(["command": "start", "name": name, "pid": pid])
        active = true
    }

    func stop() throws {
        guard active else { return }
        _ = try request(["command": "stop"])
        active = false
    }

    func mark(_ name: String) throws -> Double {
        let result = try request(["command": "mark", "name": name])
        guard let time = result["time"] as? Double else { throw E2EError.condition("Missing recording marker") }
        return time
    }

    func waitUntil(_ elapsed: Double) throws {
        try driver.wait("the recorded audio interval must finish", timeout: 15) {
            guard let state = try? self.request(nil),
                  let value = state["elapsed"] as? Double else { return false }
            return value >= elapsed
        }
    }
}
