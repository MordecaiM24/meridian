import Foundation
import Combine

@MainActor
final class MeridianViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case working(String)
        case success(String)
        case failure(String)

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .working(let message),
                 .success(let message),
                 .failure(let message):
                return message
            }
        }

        var isLoading: Bool {
            if case .working = self {
                return true
            }
            return false
        }

        var isFailure: Bool {
            if case .failure = self {
                return true
            }
            return false
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastProcessRequest: MeridianProcessRequest?
    @Published private(set) var lastResult: MeridianProcessResponse?
    @Published private(set) var whisperServerStatus: WhisperServerResponse?
    @Published private(set) var lastError: MeridianAPIError?
    @Published private(set) var experiences: [Experience] = []

    private let api: MeridianAPI
    private let experienceStore: ExperienceStore
    private let decoder: JSONDecoder

    init(
        api: MeridianAPI = MeridianAPI(),
        experienceStore: ExperienceStore = ExperienceStore()
    ) {
        self.api = api
        self.experienceStore = experienceStore
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        loadPersistedExperiences()
    }

    func reset() {
        status = .idle
        lastProcessRequest = nil
        lastResult = nil
        whisperServerStatus = nil
        lastError = nil
        experiences = []
        do {
            try persistExperiences()
        } catch {
            status = .failure("Failed to clear saved experiences: \(error.localizedDescription)")
        }
    }

    func ensureWhisperServer(port: Int = 8000, host: String = "0.0.0.0") async {
        status = .working("Ensuring Whisper server…")
        do {
            let response = try await api.ensureWhisperServer(port: port, host: host)
            whisperServerStatus = response
            lastError = nil
            status = .success("Whisper server ready on \(response.host):\(response.port)")
        } catch {
            updateErrorState(with: error)
        }
    }

    func process(
        input: String,
        output: String? = nil,
        speakers: Int? = nil,
        noDiarize: Bool = false,
        keepTemp: Bool = false,
        whisperPort: Int = 8000,
        noServer: Bool = false
    ) async {
        let request = MeridianProcessRequest(
            input: input,
            output: output,
            speakers: speakers,
            noDiarize: noDiarize,
            keepTemp: keepTemp,
            whisperPort: whisperPort,
            noServer: noServer,
            returnJSON: true
        )
        await process(request)
    }

    func process(_ request: MeridianProcessRequest) async {
        status = .working("Processing input…")
        lastProcessRequest = request
        do {
            let response = try await api.process(request)
            try handleExperienceResponse(response)
        } catch {
            updateErrorState(with: error)
        }
    }

    func upload(fileURL: URL, options: MeridianUploadOptions = MeridianUploadOptions()) async {
        status = .working("Uploading \(fileURL.lastPathComponent)…")
        do {
            var mutableOptions = options
            mutableOptions.returnJSON = true
            let response = try await api.upload(fileURL: fileURL, options: mutableOptions)
            try handleExperienceResponse(response)
        } catch {
            updateErrorState(with: error)
        }
    }

    func reportClientError(message: String) {
        lastError = nil
        status = .failure(message)
    }
    
    @discardableResult
    func deleteExperience(_ experience: Experience) -> Bool {
        guard let index = experiences.firstIndex(where: { $0.id == experience.id }) else {
            return false
        }

        let removedExperience = experiences.remove(at: index)

        do {
            try persistExperiences()
            lastError = nil
            status = .success("Deleted experience \"\(removedExperience.title)\"")
            return true
        } catch {
            experiences.insert(removedExperience, at: index)
            status = .failure("Failed to delete experience \"\(removedExperience.title)\": \(error.localizedDescription)")
            return false
        }
    }
    
    func updateSpeakerName(for experienceID: UUID, speakerID: String, newName rawName: String) {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            status = .failure("Speaker name cannot be empty.")
            return
        }
        
        guard let index = experiences.firstIndex(where: { $0.id == experienceID }) else {
            status = .failure("Could not locate the experience to update.")
            return
        }
        
        let experience = experiences[index]
        let transcript = experience.transcript
        
        var speakers = transcript.speakers ?? [:]
        let existing = speakers[speakerID]
        let updatedSpeaker = CombinedTranscript.Speaker(
            id: speakerID,
            name: trimmedName,
            label: trimmedName,
            metadata: existing?.metadata
        )
        speakers[speakerID] = updatedSpeaker
        
        let updatedTranscript = CombinedTranscript(
            segments: transcript.segments,
            speakers: speakers
        )
        
        let updatedExperience = Experience(
            id: experience.id,
            transcript: updatedTranscript,
            outputFile: experience.outputFile,
            date: experience.date
        )
        
        experiences[index] = updatedExperience
        
        do {
            try persistExperiences()
            lastError = nil
            status = .success("Renamed speaker to \"\(trimmedName)\"")
        } catch {
            experiences[index] = experience
            status = .failure("Updated speaker but failed to save: \(error.localizedDescription)")
        }
    }
    
    private func updateErrorState(with error: Error) {
        if let apiError = error as? MeridianAPIError {
            lastError = apiError
            status = .failure(apiError.localizedDescription)
        } else {
            let transportError = MeridianAPIError.transport(error)
            lastError = transportError
            status = .failure(transportError.localizedDescription)
        }
    }

    private func handleExperienceResponse(_ response: MeridianProcessResponse) throws {
        guard let dataValue = response.data else {
            let error = NSError(
                domain: "MeridianViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing transcript data from server response."]
            )
            throw MeridianAPIError.decoding(error)
        }

        let transcript = try dataValue.decode(as: CombinedTranscript.self, decoder: decoder)
        let experience = Experience(transcript: transcript, outputFile: response.outputFile)
        
        experiences.insert(experience, at: 0)

        do {
            try persistExperiences()
            lastResult = response
            lastError = nil
            status = .success("Created experience \"\(experience.title)\"")
        } catch {
            lastResult = response
            lastError = nil
            status = .failure("Created experience but failed to save locally: \(error.localizedDescription)")
        }
    }

    private func persistExperiences() throws {
        try experienceStore.save(experiences)
    }

    private func loadPersistedExperiences() {
        do {
            experiences = try experienceStore.load()
        } catch {
            status = .failure("Failed to load saved experiences: \(error.localizedDescription)")
        }
    }
}


