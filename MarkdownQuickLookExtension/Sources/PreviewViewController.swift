import AppKit
import QuickLookUI
import os.log

enum MarkdownPreviewError: LocalizedError {
    case fileReadFailed(underlying: Error)
    case fileTooLarge(actual: Int, max: Int)
    case unsupportedEncoding
    case markdownParseFailed(underlying: Error)

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
        }
    }
}

final class PreviewViewController: NSViewController, QLPreviewingController {
    private enum BlockKind {
        case paragraph
        case header(level: Int)
        case thematicBreak
    }

    private struct BlockContext {
        let key: String
        let kind: BlockKind
        let isUnorderedListItem: Bool
        let orderedOrdinal: Int?
    }

    private let logger = Logger(subsystem: "it.little-endian.madquill.quicklook", category: "preview")
    private let maxPreviewBytes = 2 * 1024 * 1024
    private let textView = NSTextView(frame: .zero)
    private let presentationIntentKey = NSAttributedString.Key("NSPresentationIntent")
    private let inlinePresentationIntentKey = NSAttributedString.Key("NSInlinePresentationIntent")
    private let listItemDelimiterKey = NSAttributedString.Key("NSListItemDelimiter")

    override func loadView() {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView
        self.view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            logger.log("Preparing preview for \(url.path, privacy: .public)")
            let attributed = try renderMarkdown(from: url)
            textView.textStorage?.setAttributedString(attributed)
            logger.log("Preview rendered successfully for \(url.lastPathComponent, privacy: .public)")
            handler(nil)
        } catch {
            let message: String
            if let localized = (error as? LocalizedError)?.errorDescription {
                message = localized
            } else {
                message = "Unexpected error while rendering preview."
            }
            textView.string = "Preview unavailable\n\n\(message)"
            logger.error("Preview error for \(url.path, privacy: .public): \(message, privacy: .public)")
            handler(nil)
        }
    }

    private func renderMarkdown(from url: URL) throws -> NSAttributedString {
        let markdownData: Data
        do {
            markdownData = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw MarkdownPreviewError.fileReadFailed(underlying: error)
        }

        guard markdownData.count <= maxPreviewBytes else {
            throw MarkdownPreviewError.fileTooLarge(actual: markdownData.count, max: maxPreviewBytes)
        }

        guard let markdown = String(data: markdownData, encoding: .utf8) else {
            throw MarkdownPreviewError.unsupportedEncoding
        }

        do {
            let semantic = try NSAttributedString(markdown: markdown, options: .init(), baseURL: url.deletingLastPathComponent())
            return styleMarkdown(semantic)
        } catch {
            throw MarkdownPreviewError.markdownParseFailed(underlying: error)
        }
    }

    private func styleMarkdown(_ semantic: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let text = semantic.string as NSString
        var index = 0
        var lastBlockKey: String?

        while index < semantic.length {
            var range = NSRange(location: 0, length: 0)
            let attrs = semantic.attributes(at: index, effectiveRange: &range)
            let runText = text.substring(with: range)
            let context = blockContext(from: attrs, fallbackLocation: range.location)

            if case .thematicBreak = context.kind {
                if output.length > 0 {
                    output.append(NSAttributedString(string: "\n\n"))
                }
                output.append(NSAttributedString(string: "—", attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 14, weight: .medium)
                ]))
                lastBlockKey = context.key
                index = range.location + range.length
                continue
            }

            let isNewBlock = context.key != lastBlockKey
            if isNewBlock && output.length > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }

            if isNewBlock {
                if let ordinal = context.orderedOrdinal {
                    output.append(NSAttributedString(string: "\(ordinal). ", attributes: baseAttributes(for: context.kind)))
                } else if context.isUnorderedListItem {
                    output.append(NSAttributedString(string: "• ", attributes: baseAttributes(for: context.kind)))
                }
            }

            var runAttributes = baseAttributes(for: context.kind)
            applyInlineAttributes(from: attrs, to: &runAttributes)
            output.append(NSAttributedString(string: runText, attributes: runAttributes))

            lastBlockKey = context.key
            index = range.location + range.length
        }

        return output.length > 0 ? output : semantic
    }

    private func blockContext(from attrs: [NSAttributedString.Key: Any], fallbackLocation: Int) -> BlockContext {
        guard let intent = attrs[presentationIntentKey] else {
            return BlockContext(
                key: "p-\(fallbackLocation)",
                kind: .paragraph,
                isUnorderedListItem: false,
                orderedOrdinal: nil
            )
        }

        let description = String(describing: intent)
        let firstLine = description.split(separator: "\n").first.map(String.init) ?? description

        let kind: BlockKind
        if firstLine.contains("Header"), let level = firstInt(in: firstLine, pattern: #"Header \(id \d+\) \((\d+)\)"#) {
            kind = .header(level: level)
        } else if firstLine.contains("ThematicBreak") {
            kind = .thematicBreak
        } else {
            kind = .paragraph
        }

        let idValue = firstInt(in: firstLine, pattern: #"id (\d+)"#) ?? fallbackLocation
        let ordinal = firstInt(in: description, pattern: #"ListItem \(id \d+\) ordinal (\d+)"#)
        let isUnordered = description.contains("UnorderedList")
        let isOrdered = description.contains("OrderedList")

        return BlockContext(
            key: "\(idValue)",
            kind: kind,
            isUnorderedListItem: isUnordered,
            orderedOrdinal: isOrdered ? ordinal : nil
        )
    }

    private func baseAttributes(for kind: BlockKind) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0

        let font: NSFont
        switch kind {
        case .header(let level):
            switch level {
            case 1:
                font = NSFont.systemFont(ofSize: 33, weight: .bold)
            case 2:
                font = NSFont.systemFont(ofSize: 27, weight: .bold)
            case 3:
                font = NSFont.systemFont(ofSize: 22, weight: .semibold)
            default:
                font = NSFont.systemFont(ofSize: 19, weight: .semibold)
            }
        case .paragraph, .thematicBreak:
            font = NSFont.systemFont(ofSize: 16)
        }

        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func applyInlineAttributes(from source: [NSAttributedString.Key: Any], to target: inout [NSAttributedString.Key: Any]) {
        if let inlineIntent = source[inlinePresentationIntentKey] as? NSNumber {
            let raw = inlineIntent.intValue
            let isCode = (raw & 4) != 0
            let isStrong = (raw & 2) != 0
            let isEmphasis = (raw & 1) != 0

            if isCode {
                target[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                target[.foregroundColor] = NSColor.systemBlue
                target[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
            } else {
                if isStrong, let font = target[.font] as? NSFont {
                    target[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if isEmphasis, let font = target[.font] as? NSFont {
                    target[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
            }
        }

        if source[listItemDelimiterKey] != nil {
            target[.foregroundColor] = NSColor.secondaryLabelColor
        }

        if let link = source[.link] {
            target[.link] = link
            target[.foregroundColor] = NSColor.linkColor
            target[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
    }

    private func firstInt(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[groupRange])
    }
}
