import Foundation
import UniformTypeIdentifiers

public struct MeridianAPIConfiguration {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!) {
        self.baseURL = baseURL
    }
}

public enum MeridianAPIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case transport(Error)
    case server(statusCode: Int, message: String?)
    case decoding(Error)
    case encoding(Error)
    case fileNotFound(URL)
    case multipartEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let string):
            return "Unable to create a valid URL from \(string)."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .transport(let error):
            return error.localizedDescription
        case .server(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Server error (\(statusCode)): \(message)"
            } else {
                return "Server error with status code \(statusCode)."
            }
        case .decoding(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .encoding(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .fileNotFound(let url):
            return "The file at \(url.path) could not be found."
        case .multipartEncodingFailed:
            return "Unable to encode multipart form data."
        }
    }
}

public struct MeridianProcessRequest: Encodable {
    public var input: String
    public var output: String?
    public var speakers: Int?
    public var noDiarize: Bool
    public var keepTemp: Bool
    public var whisperPort: Int
    public var noServer: Bool
    public var returnJSON: Bool

    public init(
        input: String,
        output: String? = nil,
        speakers: Int? = nil,
        noDiarize: Bool = false,
        keepTemp: Bool = false,
        whisperPort: Int = 8000,
        noServer: Bool = false,
        returnJSON: Bool = true
    ) {
        self.input = input
        self.output = output
        self.speakers = speakers
        self.noDiarize = noDiarize
        self.keepTemp = keepTemp
        self.whisperPort = whisperPort
        self.noServer = noServer
        self.returnJSON = returnJSON
    }
}

public struct MeridianProcessResponse: Decodable, Equatable {
    public let outputFile: String
    public let data: JSONValue?
}

public struct WhisperServerResponse: Decodable, Equatable {
    public let status: String
    public let host: String
    public let port: Int
}

public struct MeridianUploadOptions: Hashable {
    public var output: String?
    public var speakers: Int?
    public var noDiarize: Bool
    public var keepTemp: Bool
    public var whisperPort: Int
    public var noServer: Bool
    public var returnJSON: Bool

    public init(
        output: String? = nil,
        speakers: Int? = nil,
        noDiarize: Bool = false,
        keepTemp: Bool = false,
        whisperPort: Int = 8000,
        noServer: Bool = false,
        returnJSON: Bool = true
    ) {
        self.output = output
        self.speakers = speakers
        self.noDiarize = noDiarize
        self.keepTemp = keepTemp
        self.whisperPort = whisperPort
        self.noServer = noServer
        self.returnJSON = returnJSON
    }
}

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw MeridianAPIError.decoding(DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct MeridianErrorResponse: Decodable {
    let error: String
}

public final class MeridianAPI {
    public let configuration: MeridianAPIConfiguration

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: MeridianAPIConfiguration = MeridianAPIConfiguration(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func ensureWhisperServer(port: Int = 8000, host: String = "0.0.0.0") async throws -> WhisperServerResponse {
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent("ensure_whisper_server"), resolvingAgainstBaseURL: false) else {
            throw MeridianAPIError.invalidURL(configuration.baseURL.appendingPathComponent("ensure_whisper_server").absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "host", value: host)
        ]
        guard let url = components.url else {
            throw MeridianAPIError.invalidURL(components.string ?? "ensure_whisper_server")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request: request)
        return try decodeResponse(data: data, response: response, as: WhisperServerResponse.self)
    }

    public func process(_ requestBody: MeridianProcessRequest) async throws -> MeridianProcessResponse {
        var mutableBody = requestBody
        mutableBody.returnJSON = true

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("process"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try encoder.encode(mutableBody)
        } catch {
            throw MeridianAPIError.encoding(error)
        }

        let (data, response) = try await perform(request: request)
        return try decodeResponse(data: data, response: response, as: MeridianProcessResponse.self)
    }

    public func upload(fileURL: URL, options: MeridianUploadOptions = MeridianUploadOptions()) async throws -> MeridianProcessResponse {
        #if os(macOS)
        let needsSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { fileURL.stopAccessingSecurityScopedResource() } }
        #endif
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MeridianAPIError.fileNotFound(fileURL)
        }

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var mutableOptions = options
        mutableOptions.returnJSON = true

        do {
            request.httpBody = try makeMultipartBody(
                boundary: boundary,
                fileURL: fileURL,
                options: mutableOptions
            )
        } catch {
            throw error
        }

        let (data, response) = try await perform(request: request)
        return try decodeResponse(data: data, response: response, as: MeridianProcessResponse.self)
    }

    private func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw MeridianAPIError.transport(error)
        }
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse, as type: T.Type) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeridianAPIError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let message: String?
            if let errorResponse = try? decoder.decode(MeridianErrorResponse.self, from: data) {
                message = errorResponse.error
            } else if let rawMessage = String(data: data, encoding: .utf8), !rawMessage.isEmpty {
                message = rawMessage
            } else {
                message = nil
            }
            throw MeridianAPIError.server(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MeridianAPIError.decoding(error)
        }
    }

    private func makeMultipartBody(boundary: String, fileURL: URL, options: MeridianUploadOptions) throws -> Data {
        guard let boundaryData = "--\(boundary)\r\n".data(using: .utf8),
              let closingBoundaryData = "--\(boundary)--\r\n".data(using: .utf8)
        else {
            throw MeridianAPIError.multipartEncodingFailed
        }

        var body = Data()

        let filename = fileURL.lastPathComponent
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw MeridianAPIError.transport(error)
        }

        let mimeType = mimeType(for: fileURL.pathExtension)
        guard
            let dispositionData = "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8),
            let typeData = "Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)
        else {
            throw MeridianAPIError.multipartEncodingFailed
        }

        body.append(boundaryData)
        body.append(dispositionData)
        body.append(typeData)
        body.append(fileData)
        body.append(Data("\r\n".utf8))

        try appendFormFields(boundary: boundary, body: &body, options: options)

        body.append(closingBoundaryData)
        return body
    }

    private func appendFormFields(boundary: String, body: inout Data, options: MeridianUploadOptions) throws {
        func writeField(name: String, value: String) throws {
            guard
                let boundaryData = "--\(boundary)\r\n".data(using: .utf8),
                let dispositionData = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8),
                let valueData = "\(value)\r\n".data(using: .utf8)
            else {
                throw MeridianAPIError.multipartEncodingFailed
            }

            body.append(boundaryData)
            body.append(dispositionData)
            body.append(valueData)
        }

        if let output = options.output {
            try writeField(name: "output", value: output)
        }
        if let speakers = options.speakers {
            try writeField(name: "speakers", value: String(speakers))
        }

        try writeField(name: "no_diarize", value: options.noDiarize ? "true" : "false")
        try writeField(name: "keep_temp", value: options.keepTemp ? "true" : "false")
        try writeField(name: "whisper_port", value: String(options.whisperPort))
        try writeField(name: "no_server", value: options.noServer ? "true" : "false")
        try writeField(name: "return_json", value: options.returnJSON ? "true" : "false")
    }

    private func mimeType(for pathExtension: String) -> String {
        if let utType = UTType(filenameExtension: pathExtension),
           let preferred = utType.preferredMIMEType {
            return preferred
        }
        return "application/octet-stream"
    }
}

public extension JSONValue {
    func encodedData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    func string(prettyPrinted: Bool = false) throws -> String {
        let data = try encodedData(prettyPrinted: prettyPrinted)
        return String(decoding: data, as: UTF8.self)
    }

    func decode<T: Decodable>(
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        return try decoder.decode(T.self, from: encodedData())
    }
}


