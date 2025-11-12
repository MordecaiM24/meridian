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
    private let decoder: JSONDecoder

    init(api: MeridianAPI = MeridianAPI()) {
        self.api = api
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func reset() {
        status = .idle
        lastProcessRequest = nil
        lastResult = nil
        whisperServerStatus = nil
        lastError = nil
        experiences = []
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
        lastResult = response
        lastError = nil
        status = .success("Created experience \"\(experience.title)\"")
    }
}


