import Foundation
import Network
import AppKit
import Combine

class OAuthService: ObservableObject {
    private let redirectPort = 8765
    private var listener: NWListener?
    private var accessToken: String?
    private var tokenExpiry: Date?

    private let keychainService = "com.gc.CalendarSync"

    var isAuthenticated: Bool {
        loadFromKeychain(key: "refreshToken") != nil
    }

    func authenticate(clientId: String, clientSecret: String) async throws {
        let state = UUID().uuidString
        let authURL = buildAuthURL(clientId: clientId, state: state)

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.startCallbackServer(expectedState: state, continuation: continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSWorkspace.shared.open(authURL)
            }
        }

        try await exchangeCodeForTokens(code: code, clientId: clientId, clientSecret: clientSecret)
    }

    func getValidAccessToken(clientId: String, clientSecret: String) async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        try await refreshAccessToken(clientId: clientId, clientSecret: clientSecret)
        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        return token
    }

    func signOut() {
        deleteFromKeychain(key: "refreshToken")
        deleteFromKeychain(key: "accessToken")
        accessToken = nil
        tokenExpiry = nil
    }

    private func buildAuthURL(clientId: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: "http://127.0.0.1:\(redirectPort)/callback"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/calendar"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    private func startCallbackServer(expectedState: String, continuation: CheckedContinuation<String, Error>) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(redirectPort)),
              let newListener = try? NWListener(using: .tcp, on: port) else {
            continuation.resume(throwing: OAuthError.serverFailed)
            return
        }

        self.listener = newListener
        var didResume = false

        newListener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard !didResume, let data = data, let request = String(data: data, encoding: .utf8) else { return }

                let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" +
                    "<!DOCTYPE html><html><body style='font-family:sans-serif;padding:40px'>" +
                    "<h2>✓ Signed in successfully</h2><p>You can close this tab.</p></body></html>"
                connection.send(content: Data(html.utf8), completion: .contentProcessed { _ in connection.cancel() })

                if let code = self?.parseCode(from: request, expectedState: expectedState) {
                    didResume = true
                    self?.listener?.cancel()
                    self?.listener = nil
                    continuation.resume(returning: code)
                } else {
                    didResume = true
                    continuation.resume(throwing: OAuthError.invalidCallback)
                }
            }
        }

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                 print("OAuth callback server listening on 127.0.0.1:\(self.redirectPort)")
            case .failed(let error):
                print("OAuth callback server failed: \(error)")
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: error)
                }
            default:
                break
            }
        }

        newListener.start(queue: .main)
    }

    private func parseCode(from request: String, expectedState: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2,
              let urlComponents = URLComponents(string: "http://localhost\(parts[1])") else { return nil }
        let items = urlComponents.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForTokens(code: String, clientId: String, clientSecret: String) async throws {
        let params: [String: String] = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": "http://127.0.0.1:\(redirectPort)/callback",
            "grant_type": "authorization_code",
        ]
        let response = try await postTokenRequest(params: params)
        storeTokens(response)
    }

    private func refreshAccessToken(clientId: String, clientSecret: String) async throws {
        guard let refreshToken = loadFromKeychain(key: "refreshToken") else {
            throw OAuthError.notAuthenticated
        }
        let params: [String: String] = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ]
        let response = try await postTokenRequest(params: params)
        storeTokens(response)
    }

    private func postTokenRequest(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let error = decoded.error {
            throw OAuthError.tokenError("\(error): \(decoded.errorDescription ?? "")")
        }
        return decoded
    }

    private func storeTokens(_ response: TokenResponse) {
        print("storeTokens: accessToken=\(response.accessToken != nil), refreshToken=\(response.refreshToken != nil), expiresIn=\(String(describing: response.expiresIn))")
        if let token = response.accessToken {
            accessToken = token
            tokenExpiry = Date().addingTimeInterval(TimeInterval((response.expiresIn ?? 3600) - 60))
        }
        if let refresh = response.refreshToken {
            saveToKeychain(key: "refreshToken", value: refresh)
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(key: String, value: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = Data(value.utf8)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save failed for key '\(key)': OSStatus \(status)")
        } else {
            print("Keychain save succeeded for key '\(key)'")
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum OAuthError: Error, LocalizedError {
    case serverFailed
    case invalidCallback
    case notAuthenticated
    case tokenError(String)

    var errorDescription: String? {
        switch self {
        case .serverFailed: return "Failed to start local OAuth server on port 8765"
        case .invalidCallback: return "OAuth callback was invalid or state mismatch"
        case .notAuthenticated: return "Not authenticated with Google — please sign in"
        case .tokenError(let msg): return "Token error: \(msg)"
        }
    }
}
