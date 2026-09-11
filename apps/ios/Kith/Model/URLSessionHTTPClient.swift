// URLSessionHTTPClient.swift — `KithCore.HTTPClient` over `URLSession.shared`.

import Foundation
import KithCore

struct URLSessionHTTPClient: HTTPClient {
    /// Per-request timeout in seconds.
    var timeout: TimeInterval = 20

    init(timeout: TimeInterval = 20) {
        self.timeout = timeout
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = timeout
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return HTTPResponse(status: status, body: data)
        } catch let error as KithError {
            throw error
        } catch {
            throw KithError.network(error.localizedDescription)
        }
    }
}
