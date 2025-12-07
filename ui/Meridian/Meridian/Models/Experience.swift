import Foundation

struct Experience: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let date: Date
    let duration: String?
    let speakerCount: Int?
    let transcript: CombinedTranscript
    let outputFile: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case duration
        case speakerCount
        case transcript
        case outputFile
    }

    init(
        id: UUID = UUID(),
        transcript: CombinedTranscript,
        outputFile: String,
        date: Date = Date(),
        title: String? = nil
    ) {
        self.id = id
        self.transcript = transcript
        self.outputFile = outputFile
        self.date = date
        self.title = title ?? Experience.makeTitle(from: transcript)
        self.duration = Experience.makeDuration(from: transcript)
        self.speakerCount = Experience.makeSpeakerCount(from: transcript)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTranscript = try container.decode(CombinedTranscript.self, forKey: .transcript)
        transcript = decodedTranscript
        outputFile = try container.decode(String.self, forKey: .outputFile)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        title = (try container.decodeIfPresent(String.self, forKey: .title)) ?? Experience.makeTitle(from: decodedTranscript)
        duration = (try container.decodeIfPresent(String.self, forKey: .duration)) ?? Experience.makeDuration(from: decodedTranscript)
        speakerCount = (try container.decodeIfPresent(Int.self, forKey: .speakerCount)) ?? Experience.makeSpeakerCount(from: decodedTranscript)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encode(duration, forKey: .duration)
        try container.encode(speakerCount, forKey: .speakerCount)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(outputFile, forKey: .outputFile)
    }
}

extension Experience {
    private static func makeTitle(from transcript: CombinedTranscript) -> String {
        guard let text = transcript.segments.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return "Untitled"
        }

        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(3)

        let title = words.map(String.init).joined(separator: " ")
        return title.isEmpty ? "Untitled" : title
    }

    private static func makeDuration(from transcript: CombinedTranscript) -> String? {
        guard let maxEnd = transcript.estimatedDuration else {
            return nil
        }
        let totalSeconds = Int(round(maxEnd))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private static func makeSpeakerCount(from transcript: CombinedTranscript) -> Int? {
        if let speakers = transcript.speakers, !speakers.isEmpty {
            return speakers.count
        }
        let uniqueSpeakers = Set(transcript.segments.compactMap { $0.speaker })
        return uniqueSpeakers.isEmpty ? nil : uniqueSpeakers.count
    }
}


