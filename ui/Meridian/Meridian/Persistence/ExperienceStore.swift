import Foundation

struct ExperienceStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let preferredDirectory = baseURL.appendingPathComponent("Meridian", isDirectory: true)

        let resolvedDirectory: URL
        if fileManager.fileExists(atPath: preferredDirectory.path) {
            resolvedDirectory = preferredDirectory
        } else {
            do {
                try fileManager.createDirectory(
                    at: preferredDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                resolvedDirectory = preferredDirectory
            } catch {
                let fallbackDirectory = fileManager.temporaryDirectory.appendingPathComponent("Meridian", isDirectory: true)
                if !fileManager.fileExists(atPath: fallbackDirectory.path) {
                    try? fileManager.createDirectory(
                        at: fallbackDirectory,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }
                resolvedDirectory = fallbackDirectory
            }
        }

        directoryURL = resolvedDirectory
        fileURL = resolvedDirectory.appendingPathComponent("experiences.json")

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        jsonEncoder.dateEncodingStrategy = .iso8601
        encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        decoder = jsonDecoder
    }

    func load() throws -> [Experience] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([Experience].self, from: data)
    }

    func save(_ experiences: [Experience]) throws {
        let data = try encoder.encode(experiences)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        try data.write(to: fileURL, options: [.atomic])
    }
}

