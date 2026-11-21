import Foundation

/// Markdown files stay readable outside Teum and are coordinated with their file provider.
public enum MarkdownFolder {
    public struct Document: Equatable, Sendable {
        public let url: URL
        public let text: String
        fileprivate let data: Data
    }

    public static func files(in folder: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
            .filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
            .filter { url in
                let values = try url.resourceValues(forKeys: keys)
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func read(_ url: URL) throws -> Document? {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }
        var coordinationError: NSError?
        var result: Result<Document, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, error: &coordinationError) { location in
            result = Result {
                let data = try Data(contentsOf: location)
                guard let text = String(data: data, encoding: .utf8) else { throw FileError.invalidEncoding }
                return Document(url: url, text: text, data: data)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get()
    }

    public static func save(_ text: String, replacing original: Document) throws -> Document {
        let data = Data(text.utf8)
        try coordinateWrite(to: original.url) { location in
            let values = try location.resourceValues(forKeys: [.isSymbolicLinkKey, .ubiquitousItemHasUnresolvedConflictsKey])
            guard values.isSymbolicLink != true, values.ubiquitousItemHasUnresolvedConflicts != true,
                  try Data(contentsOf: location) == original.data else { throw FileError.changedOnDisk }
            try data.write(to: location, options: .atomic)
        }
        return Document(url: original.url, text: text, data: data)
    }

    /// A repeated export leaves the existing file untouched, even if it has since been edited.
    @discardableResult
    public static func create(_ text: String, at url: URL) throws -> Document {
        let data = Data(text.utf8)
        try coordinateWrite(to: url) { location in
            try data.write(to: location, options: .withoutOverwriting)
        }
        return Document(url: url, text: text, data: data)
    }

    private static func coordinateWrite(to url: URL, action: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, error: &coordinationError) { location in
            result = Result { try action(location) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    public enum FileError: LocalizedError {
        case invalidEncoding
        case changedOnDisk

        public var errorDescription: String? {
            switch self {
            case .invalidEncoding: "UTF-8 마크다운 파일만 열 수 있습니다."
            case .changedOnDisk: "다른 기기나 앱에서 파일을 변경했습니다. 현재 편집 내용은 창에 남아 있습니다. 복사해 보관한 후 폴더를 새로고침하세요."
            }
        }
    }
}
