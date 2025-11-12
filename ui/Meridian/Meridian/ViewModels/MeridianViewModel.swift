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

    private let api: MeridianAPI

    init(api: MeridianAPI = MeridianAPI()) {
        self.api = api
    }

    func reset() {
        status = .idle
        lastProcessRequest = nil
        lastResult = nil
        whisperServerStatus = nil
        lastError = nil
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
        noServer: Bool = false,
        returnJSON: Bool = false
    ) async {
        let request = MeridianProcessRequest(
            input: input,
            output: output,
            speakers: speakers,
            noDiarize: noDiarize,
            keepTemp: keepTemp,
            whisperPort: whisperPort,
            noServer: noServer,
            returnJSON: returnJSON
        )
        await process(request)
    }

    func process(_ request: MeridianProcessRequest) async {
        status = .working("Processing input…")
        lastProcessRequest = request
        do {
            let response = try await api.process(request)
            lastResult = response
            lastError = nil
            status = .success("Created output at \(response.outputFile)")
        } catch {
            updateErrorState(with: error)
        }
    }

    func upload(fileURL: URL, options: MeridianUploadOptions = MeridianUploadOptions()) async {
        status = .working("Uploading \(fileURL.lastPathComponent)…")
        do {
            let response = try await api.upload(fileURL: fileURL, options: options)
            lastResult = response
            lastError = nil
            status = .success("Created output at \(response.outputFile)")
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
}


