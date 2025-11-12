import Foundation

public struct CombinedTranscriptResponse: Codable, Equatable, Hashable {
    public let data: CombinedTranscript
    public let outputFile: String

    public init(transcript: CombinedTranscript, outputFile: String) {
        self.data = transcript
        self.outputFile = outputFile
    }
}

public struct CombinedTranscript: Codable, Equatable, Hashable {
    public struct Segment: Codable, Equatable, Hashable, Identifiable {
        public let id: String
        public let speaker: String?
        public let start: Double?
        public let end: Double?
        public let text: String
        public let words: [Word]?

        enum CodingKeys: String, CodingKey {
            case id
            case speaker
            case start
            case end
            case text
            case words
        }

        public struct Word: Codable, Equatable, Hashable {
            public let start: Double?
            public let end: Double?
            public let word: String
        }

        public init(
            id: String,
            speaker: String?,
            start: Double?,
            end: Double?,
            text: String,
            words: [Word]?
        ) {
            self.id = id
            self.speaker = speaker
            self.start = start
            self.end = end
            self.text = text
            self.words = words
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let intID = try? container.decode(Int.self, forKey: .id) {
                self.id = String(intID)
            } else if let stringID = try? container.decode(String.self, forKey: .id) {
                self.id = stringID
            } else {
                self.id = UUID().uuidString
            }

            self.speaker = try? container.decodeIfPresent(String.self, forKey: .speaker)
            self.start = try CombinedTranscript.decodeTimeValue(from: container, forKey: Segment.CodingKeys.start)
            self.end = try CombinedTranscript.decodeTimeValue(from: container, forKey: Segment.CodingKeys.end)
            self.text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self.words = try? container.decodeIfPresent([Word].self, forKey: .words)
        }
    }

    public struct Speaker: Codable, Equatable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let label: String?
        public let metadata: [String: String]?

        public enum CodingKeys: String, CodingKey {
            case id
            case name
            case label
            case metadata
        }

        public init(id: String, name: String?, label: String?, metadata: [String: String]?) {
            self.id = id
            self.name = name
            self.label = label
            self.metadata = metadata
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intID = try? container.decode(Int.self, forKey: .id) {
                self.id = String(intID)
            } else if let stringID = try? container.decode(String.self, forKey: .id) {
                self.id = stringID
            } else {
                self.id = UUID().uuidString
            }
            self.name = try? container.decodeIfPresent(String.self, forKey: .name)
            self.label = try? container.decodeIfPresent(String.self, forKey: .label)
            self.metadata = try? container.decodeIfPresent([String: String].self, forKey: .metadata)
        }
    }
    
    public struct SpeakerInfo: Codable, Equatable, Hashable {
        public let label: String?
        public let color: String? // make this optional, likely String? or a custom Color type
    }

    public let segments: [Segment]
    public let speakers: [String: Speaker]?

    public init(segments: [Segment], speakers: [String: Speaker]?) {
        self.segments = segments
        self.speakers = speakers
    }

    public var estimatedDuration: TimeInterval? {
        segments.compactMap { $0.end }.max()
    }
}

extension CombinedTranscript {
    private static func decodeTimeValue(
        from container: KeyedDecodingContainer<CombinedTranscript.Segment.CodingKeys>,
        forKey key: CombinedTranscript.Segment.CodingKeys
    ) throws -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}

