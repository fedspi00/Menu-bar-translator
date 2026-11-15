import Foundation

struct TranslationResult {
    let text: String
    /// Source language Google reported, normalized to our code list.
    let detected: String?
}

enum TranslateError: LocalizedError {
    case rateLimited
    case http(Int)
    case badResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Google is rate-limiting requests. Wait a few seconds and try again."
        case .http(let code):
            return "Google Translate returned an error (HTTP \(code))."
        case .badResponse:
            return "Couldn't read the response from Google Translate."
        case .offline:
            return "No internet connection."
        }
    }
}

/// Talks to the same free endpoints the Google Translate web app and the
/// Chrome translate extension use. No API key, no quota to configure.
enum GoogleTranslate {

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    static func translate(_ text: String, from source: String, to target: String) async throws -> TranslationResult {
        do {
            return try await single(text, from: source, to: target)
        } catch let error as TranslateError {
            // The primary endpoint occasionally answers with a captcha page.
            // The Chrome-extension endpoint is served separately and usually
            // still works, so fall back to it before surfacing the failure.
            if case .badResponse = error {
                return try await dictChrome(text, from: source, to: target)
            }
            if case .rateLimited = error {
                return try await dictChrome(text, from: source, to: target)
            }
            throw error
        }
    }

    // MARK: - Endpoints

    /// translate.google.com/translate_a/single — returns per-sentence segments
    /// plus the detected source language.
    private static func single(_ text: String, from source: String, to target: String) async throws -> TranslationResult {
        var components = URLComponents(string: "https://translate.google.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "at"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
        ]

        let json = try await postForJSON(components.url!, query: text)
        guard let root = json as? [Any], let segments = root.first as? [Any] else {
            throw TranslateError.badResponse
        }

        var translated = ""
        for segment in segments {
            if let parts = segment as? [Any], let piece = parts.first as? String {
                translated += piece
            }
        }
        guard !translated.isEmpty else { throw TranslateError.badResponse }

        let detected = (root.count > 2 ? root[2] as? String : nil).map(Languages.normalize)
        return TranslationResult(text: translated, detected: detected)
    }

    /// clients5.google.com/translate_a/t — the Chrome translate extension
    /// endpoint. Returns either ["text"] or [["text","detected"]].
    private static func dictChrome(_ text: String, from source: String, to target: String) async throws -> TranslationResult {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/t")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
        ]

        let json = try await postForJSON(components.url!, query: text)

        if let strings = json as? [String], let first = strings.first {
            return TranslationResult(text: first, detected: nil)
        }
        if let rows = json as? [[Any]], let row = rows.first {
            let translated = row.first as? String ?? ""
            guard !translated.isEmpty else { throw TranslateError.badResponse }
            let detected = (row.count > 1 ? row[1] as? String : nil).map(Languages.normalize)
            return TranslationResult(text: translated, detected: detected)
        }
        throw TranslateError.badResponse
    }

    // MARK: - Transport

    /// Sends the text in the request body so long passages aren't capped by
    /// URL length limits.
    private static func postForJSON(_ url: URL, query text: String) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = "q=\(formEncode(text))".data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dataNotAllowed:
                throw TranslateError.offline
            case .cancelled:
                throw CancellationError()
            default:
                throw error
            }
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 429 ? TranslateError.rateLimited : TranslateError.http(http.statusCode)
        }

        // A captcha or consent interstitial comes back as markup, not JSON —
        // "<html", "<!DOCTYPE", or an XML preamble.
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        if let firstByte = data.first(where: { !whitespace.contains($0) }),
           firstByte == UInt8(ascii: "<") {
            throw TranslateError.rateLimited
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw TranslateError.badResponse
        }
        return json
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
