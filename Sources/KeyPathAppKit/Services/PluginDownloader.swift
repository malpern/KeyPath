import Foundation
import KeyPathCore

/// Downloads a file to a temporary location with byte-level progress reporting
/// and cooperative cancellation.
///
/// Bridges `URLSessionDownloadDelegate` callbacks into async/await: the download
/// task is cancelled when the awaiting `Task` is cancelled, and progress is
/// surfaced via `progressHandler` (called on the session's delegate queue, so
/// hop to the main actor inside the handler before touching UI state).
// SAFETY: @unchecked Sendable — `continuation`/`task` are written once before
// `resume()` starts delivering delegate callbacks, so there is no concurrent
// access; the continuation is resumed exactly once and then niled.
final class PluginDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let progressHandler: @Sendable (Double) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask?

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Downloads `url`, returning a temp-file URL the caller is responsible for
    /// removing. Throws `URLError`/`CancellationError` on failure or cancellation.
    func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                continuation = cont
                let downloadTask = session.downloadTask(with: url)
                task = downloadTask
                downloadTask.resume()
            }
        } onCancel: {
            task?.cancel()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The system deletes `location` once this delegate returns, so move the
        // file out synchronously before resuming.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        // On success the continuation was already resumed in didFinishDownloadingTo.
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        session.finishTasksAndInvalidate()
    }
}
