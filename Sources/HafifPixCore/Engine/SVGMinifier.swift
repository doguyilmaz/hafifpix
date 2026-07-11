import Foundation

/// Conservative native SVG minifier: strips comments, editor metadata,
/// DOCTYPE/XML declaration, and inter-element whitespace. Deliberately avoids
/// risky transforms (path rewriting, precision reduction) — correctness first.
public enum SVGMinifier {
    private static let junkElements: Set<String> = [
        "metadata", "sodipodi:namedview", "title", "desc",
    ]
    private static let junkNamespaces = ["inkscape", "sodipodi", "sketch", "figma", "dc", "cc", "rdf"]

    public static func minify(_ data: Data) throws -> Data {
        let document = try XMLDocument(data: data, options: [.nodePreserveCDATA])
        guard let root = document.rootElement(), root.name?.lowercased() == "svg" else {
            throw MinifyError.notSVG
        }

        clean(element: root)

        var output = root.xmlString(options: [.nodeCompactEmptyElement])
        // XMLDocument can leave runs of whitespace between attributes/tags intact;
        // the tree walk already removed whitespace-only text nodes, so what's
        // left is semantic. Just trim the outside.
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let result = output.data(using: .utf8) else { throw MinifyError.encodingFailed }

        // Sanity: the result must still parse and keep the svg root.
        let reparsed = try XMLDocument(data: result, options: [])
        guard reparsed.rootElement()?.name?.lowercased() == "svg" else {
            throw MinifyError.verificationFailed
        }
        return result
    }

    private static func clean(element: XMLElement) {
        var indicesToRemove: [Int] = []

        for (index, child) in (element.children ?? []).enumerated() {
            switch child.kind {
            case .comment, .processingInstruction, .DTDKind:
                indicesToRemove.append(index)
            case .text:
                if let text = child.stringValue,
                   text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   (element.children?.count ?? 0) > 1 {
                    indicesToRemove.append(index)
                }
            case .element:
                guard let childElement = child as? XMLElement, let name = childElement.name?.lowercased() else { break }
                if junkElements.contains(name) || junkNamespaces.contains(where: { name.hasPrefix("\($0):") }) {
                    indicesToRemove.append(index)
                } else {
                    clean(element: childElement)
                }
            default:
                break
            }
        }

        for index in indicesToRemove.reversed() {
            element.removeChild(at: index)
        }

        for attribute in element.attributes ?? [] {
            guard let name = attribute.name?.lowercased() else { continue }
            let isJunkAttr = junkNamespaces.contains { name.hasPrefix("\($0):") }
            let isJunkNamespaceDecl = junkNamespaces.contains { name == "xmlns:\($0)" }
            if isJunkAttr || isJunkNamespaceDecl {
                element.removeAttribute(forName: attribute.name!)
            }
        }

        // xmlns:foo declarations are namespace nodes, not attributes.
        for namespace in element.namespaces ?? [] {
            if let prefix = namespace.name?.lowercased(), junkNamespaces.contains(prefix) {
                element.removeNamespace(forPrefix: prefix)
            }
        }
    }

    public enum MinifyError: Error, LocalizedError {
        case notSVG
        case encodingFailed
        case verificationFailed

        public var errorDescription: String? {
            switch self {
            case .notSVG: LC("Not an SVG document")
            case .encodingFailed: LC("Could not encode minified SVG")
            case .verificationFailed: LC("Minified SVG failed verification")
            }
        }
    }
}
