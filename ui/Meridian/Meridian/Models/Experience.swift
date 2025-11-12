import Foundation

struct Experience: Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: Date
    let duration: String?
    let speakerCount: Int?
    let transcript: CombinedTranscript
    let outputFile: String

    init(
        transcript: CombinedTranscript,
        outputFile: String,
        date: Date = Date()
    ) {
        self.id = UUID()
        self.transcript = transcript
        self.outputFile = outputFile
        self.date = date
        self.title = Experience.makeTitle(from: transcript)
        self.duration = Experience.makeDuration(from: transcript)
        self.speakerCount = Experience.makeSpeakerCount(from: transcript)
    }
}

extension Experience {
    private static func makeTitle(from transcript: CombinedTranscript) -> String {
        guard let text = transcript.segments.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return "Untitled Experience"
        }

        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(3)

        let title = words.map(String.init).joined(separator: " ")
        return title.isEmpty ? "Untitled Experience" : title
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


