import Foundation

public enum MarkdownFilename {
    public static func stem(for text: String) -> String {
        let title = MarkdownDocument.title(in: text)
        let forbidden = CharacterSet(charactersIn: "/:\\")
        var safe = ""
        for scalar in title.unicodeScalars {
            if forbidden.contains(scalar) || scalar.properties.generalCategory == .control {
                safe.append("-")
            } else {
                safe.unicodeScalars.append(scalar)
            }
        }
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        var limited = ""
        var bytes = 0
        for character in safe.trimmingCharacters(in: edges) {
            let count = String(character).decomposedStringWithCanonicalMapping.utf8.count
            guard bytes + count <= 160 else { break }
            limited.append(character)
            bytes += count
        }
        let stem = limited.trimmingCharacters(in: edges)
        return stem.isEmpty ? "새 메모" : stem
    }

    public static func matches(_ filename: String, stem: String) -> Bool {
        guard (filename as NSString).pathExtension.lowercased() == "md" else { return false }
        let base = (filename as NSString).deletingPathExtension
        if base == stem { return true }
        let prefix = stem + " ("
        guard base.hasPrefix(prefix), base.hasSuffix(")") else { return false }
        return Int(base.dropFirst(prefix.count).dropLast()).map { $0 > 1 } == true
    }

    public static func available(in directory: URL, stem: String) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let taken = Set(names.map { $0.lowercased() })
        var number = 1
        while true {
            let name = number == 1 ? "\(stem).md" : "\(stem) (\(number)).md"
            if !taken.contains(name.lowercased()) { return directory.appendingPathComponent(name) }
            number += 1
        }
    }

    public static func create(_ text: String, in directory: URL, stem: String? = nil) throws -> MarkdownFolder.Document {
        let stem = stem ?? self.stem(for: text)
        for _ in 0..<5 {
            let url = try available(in: directory, stem: stem)
            do {
                return try MarkdownFolder.create(text, at: url)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
