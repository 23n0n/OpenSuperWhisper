import Combine
import Foundation

class ModelDownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let progressCallback: (Double) -> Void
    private var expectedContentLength: Int64 = 0
    var completionHandler: ((URL?, Error?) -> Void)?
    weak var downloadTask: URLSessionDownloadTask?
    
    init(progressCallback: @escaping (Double) -> Void) {
        self.progressCallback = progressCallback
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let error = Self.validationError(for: downloadTask.response) {
            completionHandler?(nil, error)
            return
        }
        completionHandler?(location, nil)
    }
    
    static func validationError(for response: URLResponse?) -> Error? {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        return NSError(
            domain: "WhisperModelManager",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Model server returned HTTP \(httpResponse.statusCode). Please try again later."]
        )
    }
    
    static func progressFraction(totalBytesWritten: Int64, expectedContentLength: Int64) -> Double? {
        guard expectedContentLength > 0 else { return nil }
        return min(Double(totalBytesWritten) / Double(expectedContentLength), 1.0)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if expectedContentLength <= 0 {
            expectedContentLength = totalBytesExpectedToWrite
        }
        guard let progress = Self.progressFraction(totalBytesWritten: totalBytesWritten, expectedContentLength: expectedContentLength) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.progressCallback(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(nil, error)
        } else {
        }
    }
}

class WhisperModelManager {
    static let shared = WhisperModelManager()

    /// The model the app ships inside its own bundle.
    static let defaultModelName = "ggml-tiny.en.bin"

    private static let modelsDirectoryName = "whisper-models"
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    private let downloadTasksLock = NSLock()

    /// `~/Library/Application Support/<bundle id>/whisper-models/`
    ///
    /// Static so the preference migration can tell an app-owned model path from
    /// a foreign one without instantiating the manager.
    static var modelsDirectory: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "ru.starmel.OpenSuperWhisper"
        return applicationSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent(modelsDirectoryName)
    }

    var modelsDirectory: URL { Self.modelsDirectory }
    
    private init() {
        createModelsDirectoryIfNeeded()
        copyDefaultModelIfNeeded()
    }
    
    private func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create models directory: \(error)")
        }
    }
    
    private func copyDefaultModelIfNeeded() {
        let defaultModelName = Self.defaultModelName
        let destinationURL = modelsDirectory.appendingPathComponent(defaultModelName)
        
        // Check if model already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }
        
        // Look for the model in the bundle
        if let bundleURL = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
            do {
                try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
                print("Copied default model to: \(destinationURL.path)")
            } catch {
                print("Failed to copy default model: \(error)")
            }
        }
    }

    // Call this on every startup to ensure at least one model is present
    public func ensureDefaultModelPresent() {
        let defaultModelName = Self.defaultModelName
        let defaultModelURL = modelsDirectory.appendingPathComponent(defaultModelName)
        if !FileManager.default.fileExists(atPath: defaultModelURL.path) {
            copyDefaultModelIfNeeded()
        }

        // A selection that points at a file which is not there anymore (the
        // checkout it came from was moved, the file was deleted) would fail
        // every dictation with contextInitializationFailed. Point it at the
        // model the app owns instead.
        let prefs = AppPreferences.shared
        if let stored = prefs.selectedWhisperModelPath,
           !stored.isEmpty,
           !FileManager.default.fileExists(atPath: stored),
           FileManager.default.fileExists(atPath: defaultModelURL.path) {
            print("Selected whisper model \(stored) is gone; falling back to the bundled one")
            prefs.selectedWhisperModelPath = defaultModelURL.path
        }
    }
    
    func getAvailableModels() -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "bin" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("Failed to get available models: \(error)")
            return []
        }
    }
    
    // Download model with progress callback using delegate
    func downloadModel(url: URL, name: String, progressCallback: @escaping (Double) -> Void) async throws {
        let destinationURL = modelsDirectory.appendingPathComponent(name)
        
        // Check if model already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            print("Model already exists at: \(destinationURL.path)")
            DispatchQueue.main.async {
                progressCallback(1.0)
            }
            return
        }
        
        print("Starting model download:")
        print("- URL: \(url.absoluteString)")
        print("- Destination: \(destinationURL.path)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ModelDownloadDelegate(progressCallback: progressCallback)
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 24 * 60 * 60
            
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
            print("Initiating download...")
            
            // Create a download task without completion handler
            let downloadTask = session.downloadTask(with: url)
            delegate.downloadTask = downloadTask
            
            // Store task for cancellation
            downloadTasksLock.lock()
            activeDownloadTasks[name] = downloadTask
            downloadTasksLock.unlock()
            
            // Add completion handling to delegate
            delegate.completionHandler = { [weak self] location, error in
                session.finishTasksAndInvalidate()
                
                // Remove task from active downloads
                self?.downloadTasksLock.lock()
                let isCurrent = self?.activeDownloadTasks[name] === downloadTask
                if isCurrent { self?.activeDownloadTasks.removeValue(forKey: name) }
                self?.downloadTasksLock.unlock()
                guard isCurrent else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                // Check if cancelled
                if let error = error as? URLError, error.code == .cancelled {
                    print("Download cancelled")
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                if let error = error {
                    print("Download failed with error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let location = location else {
                    let error = NSError(domain: "WhisperModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No download URL received"])
                    continuation.resume(throwing: error)
                    return
                }
                
                do {
                    print("Download completed. Moving file to destination...")
                    try FileManager.default.moveItem(at: location, to: destinationURL)
                    print("Model successfully saved to: \(destinationURL.path)")
                    
                    DispatchQueue.main.async {
                        progressCallback(1.0)
                    }
                    
                    continuation.resume(returning: ())
                } catch {
                    print("Failed to move downloaded file: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            downloadTask.resume()
        }
    }
    
    // Cancel download task
    func cancelDownload(name: String) {
        downloadTasksLock.lock()
        defer { downloadTasksLock.unlock() }
        
        if let task = activeDownloadTasks[name] {
            task.cancel()
            activeDownloadTasks.removeValue(forKey: name)
            print("Cancelled download for: \(name)")
        }
    }
    
    // Check if specific model is downloaded
    func isModelDownloaded(name: String) -> Bool {
        let modelPath = modelsDirectory.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: modelPath)
    }
}
