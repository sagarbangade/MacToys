import Foundation

/// Manages a Python sidecar process that runs the T5-based GEC model.
/// Communicates via JSON lines over stdin/stdout.
actor GECSidecar {
    static let shared = GECSidecar()

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var isReady = false
    private var pendingRequests: [String: CheckedContinuation<String, Error>] = [:]
    private var requestCounter = 0
    private var buffer = Data()

    enum GECError: Error, LocalizedError {
        case notReady
        case processNotRunning
        case timeout
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notReady: return "GEC model is not ready yet"
            case .processNotRunning: return "GEC sidecar process is not running"
            case .timeout: return "GEC request timed out"
            case .invalidResponse: return "Invalid response from GEC sidecar"
            }
        }
    }

    /// Start the Python sidecar process if not already running.
    func start() async throws {
        guard process == nil || process?.isRunning != true else { return }

        isReady = false
        buffer = Data()

        let proc = Process()

        // Find uv or python3
        let uvPath = findExecutable("uv")
        let gecScript = findGECScript()

        if let uv = uvPath {
            proc.executableURL = URL(fileURLWithPath: uv)
            proc.arguments = [
                "run",
                "--with", "mlx",
                "--with", "transformers",
                "--with", "sentencepiece",
                "--with", "litellm",
                "--with", "llama-cpp-python",
                "python3", gecScript,
            ]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = [gecScript]
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading

        // Log stderr in background
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("[GEC stderr] \(str)", terminator: "")
            }
        }

        // Read stdout in background
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.handleOutput(data) }
        }

        try proc.run()
        self.process = proc
        print("[GECSidecar] Process started (PID: \(proc.processIdentifier))")

        // Wait for "ready" status
        try await waitForReady(timeout: 300) // 5 min timeout for first download
    }

    /// Correct grammar or apply instruction to the given text.
    func correct(text: String, instruction: String = "") async throws -> String {
        guard isReady else { throw GECError.notReady }
        guard let stdinHandle = stdin, process?.isRunning == true else {
            throw GECError.processNotRunning
        }

        requestCounter += 1
        let reqId = "\(requestCounter)"
        
        let defaults = UserDefaults.standard
        let backendType = defaults.string(forKey: "gecBackendType") ?? "local"
        let provider = defaults.string(forKey: "gecApiProvider") ?? "groq"
        let model = defaults.string(forKey: "gecApiModel") ?? "groq/qwen/qwen3.8-27b"
        let apiKey = defaults.string(forKey: "gecApiKey") ?? ""
        let modelPath = defaults.string(forKey: "gecModelPath") ?? ""

        let request: [String: Any] = [
            "id": reqId,
            "text": text,
            "backend_type": backendType,
            "provider": provider,
            "model": model,
            "api_key": apiKey,
            "model_path": modelPath,
            "instruction": instruction
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        var line = jsonData
        line.append(contentsOf: [0x0A]) // newline
        stdinHandle.write(line)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[reqId] = continuation
        }
    }

    /// Send a command to the sidecar.
    func sendCommand(_ cmd: String) {
        guard let stdinHandle = stdin, process?.isRunning == true else { return }
        let payload = #"{"command":"\#(cmd)"}"# + "\n"
        stdinHandle.write(payload.data(using: .utf8)!)
    }
    
    /// Stop the sidecar process.
    func stop() {
        if let stdinHandle = stdin, process?.isRunning == true {
            let shutdown = #"{"command":"shutdown"}"# + "\n"
            stdinHandle.write(shutdown.data(using: .utf8)!)
        }
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        isReady = false
        pendingRequests.removeAll()
    }

    // MARK: - Private

    private func handleOutput(_ data: Data) {
        buffer.append(data)

        // Process complete lines
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[(newlineIndex + 1)...])

            guard let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // Handle status messages
            if let status = json["status"] as? String {
                print("[GECSidecar] Status: \(status)")
                if status == "ready" {
                    isReady = true
                }
                continue
            }

            // Handle correction responses
            if let reqId = json["id"] as? String {
                if let errorMsg = json["error"] as? String {
                    if let continuation = pendingRequests.removeValue(forKey: reqId) {
                        continuation.resume(returning: "Error: \(errorMsg)")
                    }
                } else if let corrected = json["corrected"] as? String {
                    if let continuation = pendingRequests.removeValue(forKey: reqId) {
                        continuation.resume(returning: corrected)
                    }
                }
            }
        }
    }

    private func waitForReady(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady {
            if Date() > deadline {
                throw GECError.timeout
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private func findGECScript() -> String {
        // Look in the app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "gec_server", ofType: "py") {
            return bundlePath
        }
        // Fallback: look relative to the binary
        let binaryDir = Bundle.main.bundlePath
        let appContents = (binaryDir as NSString).deletingLastPathComponent
        let resourcesPath = (appContents as NSString).appendingPathComponent("Resources/gec_server.py")
        if FileManager.default.fileExists(atPath: resourcesPath) {
            return resourcesPath
        }
        // Development fallback
        return "Resources/gec_server.py"
    }

    private func findExecutable(_ name: String) -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "\(NSHomeDirectory())/.cargo/bin/\(name)",
        ]
        return commonPaths.first { FileManager.default.fileExists(atPath: $0) }
    }
}
