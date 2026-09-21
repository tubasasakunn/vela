import AppKit
import Foundation
import Vision

public enum ScreenTextCaptureError: LocalizedError {
    case cancelled
    case imageUnavailable
    case noTextFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "スクリーンショットをキャンセルしました。"
        case .imageUnavailable: return "撮影したスクリーンショットを読み取れませんでした。"
        case .noTextFound: return "スクリーンショット内にコピーできる文字列が見つかりませんでした。"
        case let .captureFailed(message): return "スクリーンショットを撮影できませんでした。\(message)"
        }
    }
}

struct RecognizedScreenTextLine {
    let text: String
    let bounds: CGRect
}

/// Uses macOS's familiar region-selection UI, then recognizes the captured image
/// locally with Vision. The screenshot is never written to disk by Vela.
public enum ScreenTextCapture {
    public static func captureInteractively(completion: @escaping (Result<String, Error>) -> Void) {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { process in
            guard process.terminationStatus == 0 else {
                let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(.failure(ScreenTextCaptureError.captureFailed(message)))
                return
            }
            guard pasteboard.changeCount != initialChangeCount else {
                completion(.failure(ScreenTextCaptureError.cancelled))
                return
            }
            guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                completion(.failure(ScreenTextCaptureError.imageUnavailable))
                return
            }
            recognize(cgImage, completion: completion)
        }
        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    public static func recognize(_ image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                completion(.failure(error))
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lines = observations.compactMap { observation -> RecognizedScreenTextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedScreenTextLine(text: candidate.string, bounds: observation.boundingBox)
            }
            let text = arrangedText(lines)
            completion(text.isEmpty ? .failure(ScreenTextCaptureError.noTextFound) : .success(text))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Vision does not promise observation order. Group nearby baselines before
    /// reading left-to-right so multi-column captures remain legible.
    static func arrangedText(_ lines: [RecognizedScreenTextLine]) -> String {
        let byTop = lines.sorted { $0.bounds.maxY > $1.bounds.maxY }
        var rows: [[RecognizedScreenTextLine]] = []
        for line in byTop {
            guard let last = rows.indices.last else {
                rows.append([line])
                continue
            }
            let averageTop = rows[last].map(\.bounds.maxY).reduce(0, +) / CGFloat(rows[last].count)
            let averageHeight = rows[last].map(\.bounds.height).reduce(0, +) / CGFloat(rows[last].count)
            if abs(line.bounds.maxY - averageTop) <= max(0.01, averageHeight * 0.6) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
