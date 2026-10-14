import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import os.log

enum MarkdownPreviewError: LocalizedError {
    case fileReadFailed(underlying: Error)
    case fileTooLarge(actual: Int, max: Int)
    case unsupportedEncoding
    case markdownParseFailed(underlying: Error)
    case htmlConversionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let underlying):
            return "Could not read file: \(underlying.localizedDescription)"
        case .fileTooLarge(let actual, let max):
            return "File is too large to preview (\(actual) bytes, limit \(max) bytes)."
        case .unsupportedEncoding:
            return "Only UTF-8 Markdown files are supported for preview."
        case .markdownParseFailed(let underlying):
            return "Could not parse Markdown: \(underlying.localizedDescription)"
        case .htmlConversionFailed(let underlying):
            return "Could not render preview output: \(underlying.localizedDescription)"
        }
    }
}

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private let logger = Logger(subsystem: "com.example.madquill.quicklook", category: "preview")
    private let maxPreviewBytes = 2 * 1024 * 1024

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        do {
            let markdownData: Data
            do {
                markdownData = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
            } catch {
                throw MarkdownPreviewError.fileReadFailed(underlying: error)
            }
            guard markdownData.count <= maxPreviewBytes else {
                throw MarkdownPreviewError.fileTooLarge(actual: markdownData.count, max: maxPreviewBytes)
            }

            guard let markdown = String(data: markdownData, encoding: .utf8) else {
                throw MarkdownPreviewError.unsupportedEncoding
            }

            let attributed = try parseMarkdown(markdown, baseURL: request.fileURL.deletingLastPathComponent())
            let html = try attributedHTML(from: attributed)
            return htmlReply(from: html)
        } catch let error as MarkdownPreviewError {
            logger.error("Preview error for \(request.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return errorReply(message: error.localizedDescription)
        } catch {
            logger.error("Unexpected preview error for \(request.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return errorReply(message: "Unexpected error while rendering preview.")
        }
    }

    private func parseMarkdown(_ markdown: String, baseURL: URL) throws -> NSAttributedString {
        do {
            return try NSAttributedString(markdown: markdown, options: .init(), baseURL: baseURL)
        } catch {
            throw MarkdownPreviewError.markdownParseFailed(underlying: error)
        }
    }

    private func attributedHTML(from attributed: NSAttributedString) throws -> Data {
        let range = NSRange(location: 0, length: attributed.length)
        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html
        ]

        do {
            return try attributed.data(from: range, documentAttributes: options)
        } catch {
            throw MarkdownPreviewError.htmlConversionFailed(underlying: error)
        }
    }

    private func htmlReply(from htmlData: Data) -> QLPreviewReply {
        QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 960, height: 1200)) { reply in
            reply.stringEncoding = .utf8
            return htmlData
        }
    }

    private func errorReply(message: String) -> QLPreviewReply {
        let escaped = escapeHTML(message)
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              margin: 24px;
              color: #1d1d1f;
            }
            .box {
              border-radius: 12px;
              border: 1px solid #d2d2d7;
              padding: 16px;
              background: #f5f5f7;
            }
            h1 { margin-top: 0; font-size: 20px; }
            p { margin-bottom: 0; line-height: 1.4; }
          </style>
        </head>
        <body>
          <div class="box">
            <h1>Preview unavailable</h1>
            <p>\(escaped)</p>
          </div>
        </body>
        </html>
        """
        let data = Data(html.utf8)
        return htmlReply(from: data)
    }

    private func escapeHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
