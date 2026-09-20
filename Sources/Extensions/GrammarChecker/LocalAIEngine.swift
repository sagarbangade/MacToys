import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

@MainActor
@Observable
class LocalAIEngine {
    static let shared = LocalAIEngine()
    
    var isModelLoaded = false
    var downloadProgress: Double = 0.0
    var modelStatus: String = "Not loaded"
    
    private var modelContainer: ModelContainer?
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration = 0
    
    // Tiny, fast, Apple-optimized Llama-3.2 for MLX (4-bit)
    let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    
    private init() {}
    
    func loadModelIfNeeded() async {
        guard modelContainer == nil else { return }

        // Multiple input sessions can request a prediction at once.  They must
        // await one download/load operation rather than allocate duplicate MLX
        // models or download the same checkpoint repeatedly.
        if let loadingTask {
            await loadingTask.value
            return
        }

        modelStatus = "Downloading model..."

        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadModel(generation: generation)
        }
        loadingTask = task
        await task.value
    }

    func cancelLoading() {
        loadGeneration += 1
        loadingTask?.cancel()
        loadingTask = nil
        if modelContainer == nil {
            modelStatus = "Not loaded"
            downloadProgress = 0
        }
    }

    private func loadModel(generation: Int) async {
        defer {
            // A cancelled, older request must not clear a task started after
            // the module was enabled again.
            if loadGeneration == generation {
                loadingTask = nil
            }
        }

        do {
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelURL = appSupport.appendingPathComponent("MacToys/Models/SmolLM-135M-GEC")
            
            let container = try await loadModelContainer(
                from: modelURL,
                using: #huggingFaceTokenizerLoader()
            )

            guard !Task.isCancelled, loadGeneration == generation else { return }
            self.modelContainer = container
            self.isModelLoaded = true
            self.modelStatus = "Ready"
            
        } catch is CancellationError {
            if loadGeneration == generation, modelContainer == nil {
                modelStatus = "Not loaded"
                downloadProgress = 0
            }
        } catch {
            guard loadGeneration == generation else { return }
            self.modelStatus = "Error: \(error.localizedDescription)"
            print("Failed to load MLX model: \(error)")
        }
    }
    
    func streamPrediction(contextText: String, systemPrompt: String? = nil, onToken: @escaping (String) -> Void) async {
        guard let container = modelContainer else { return }
        
        do {
            let defaultSystem = "You are an intelligent code and text completion engine. Continue the user's text naturally and seamlessly. Output ONLY the completion text, no chat, no formatting, no preamble."
            let messages: [Chat.Message] = [
                .init(role: .system, content: systemPrompt ?? defaultSystem),
                .init(role: .user, content: contextText)
            ]
            
            let prompt = UserInput(prompt: .chat(messages))
            let input = try await container.prepare(input: prompt)
            
            let parameters = GenerateParameters(
                maxTokens: 512,
                temperature: 0.2,
                topP: 0.9
            )
            
            let stream = try await container.generate(input: input, parameters: parameters)
            
            for try await generation in stream {
                if let chunk = generation.chunk {
                    onToken(chunk)
                }
            }
        } catch {
            print("MLX Generation error: \(error)")
        }
    }
}
