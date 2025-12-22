import Foundation
import AuthenticationServices

/// Google OAuth 2.0 authentication service
class GoogleOAuthService: NSObject, ObservableObject {
    
    // OAuth configuration - User needs to replace with their own
    static var clientId = ""  // Set this in Settings
    static var clientSecret = "" // Set this in Settings (for desktop apps)
    
    private let redirectUri = "com.macmessagebackup:/oauth2callback"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    
    // Scopes for Gmail and Calendar access
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",      // Gmail read/write
        "https://www.googleapis.com/auth/calendar.events",   // Calendar events
        "https://www.googleapis.com/auth/contacts.readonly"  // Read contacts
    ].joined(separator: " ")
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var error: String?
    
    private var authSession: ASWebAuthenticationSession?
    private var presentationContextProvider: PresentationContextProvider?
    
    override init() {
        super.init()
        loadTokens()
    }
    
    // MARK: - OAuth Flow
    
    /// Start OAuth authentication flow
    func authenticate() {
        guard !GoogleOAuthService.clientId.isEmpty else {
            error = "Please configure Client ID in Settings"
            return
        }
        
        let authURL = buildAuthorizationURL()
        
        presentationContextProvider = PresentationContextProvider()
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.macmessagebackup"
        ) { [weak self] callbackURL, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
                return
            }
            
            guard let callbackURL = callbackURL,
                  let code = self?.extractCode(from: callbackURL) else {
                DispatchQueue.main.async {
                    self?.error = "Failed to get authorization code"
                }
                return
            }
            
            Task {
                await self?.exchangeCodeForTokens(code)
            }
        }
        
        authSession?.presentationContextProvider = presentationContextProvider
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.start()
    }
    
    /// Build OAuth authorization URL
    private func buildAuthorizationURL() -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthService.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }
    
    /// Extract authorization code from callback URL
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    /// Exchange authorization code for tokens
    @MainActor
    private func exchangeCodeForTokens(_ code: String) async {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": GoogleOAuthService.clientId,
            "client_secret": GoogleOAuthService.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                error = "Token exchange failed"
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.isAuthenticated = true
            
            // Save tokens
            saveTokens()
            
            // Fetch user email
            await fetchUserInfo()
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Refresh access token
    @MainActor
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw OAuthError.noRefreshToken
        }
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": GoogleOAuthService.clientId,
            "client_secret": GoogleOAuthService.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        saveTokens()
    }
    
    /// Fetch user info (email)
    @MainActor
    private func fetchUserInfo() async {
        guard let token = accessToken else { return }
        
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
            self.userEmail = userInfo.email
        } catch {
            print("Failed to fetch user info: \(error)")
        }
    }
    
    /// Sign out
    @MainActor
    func signOut() {
        accessToken = nil
        refreshToken = nil
        userEmail = nil
        isAuthenticated = false
        deleteTokens()
    }
    
    // MARK: - Token Storage
    
    private let tokenPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/MacMessageBackup/oauth_tokens.json")
    
    private func saveTokens() {
        let tokens = StoredTokens(
            accessToken: accessToken ?? "",
            refreshToken: refreshToken ?? "",
            userEmail: userEmail ?? ""
        )
        
        do {
            let directory = tokenPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tokens)
            try data.write(to: tokenPath)
        } catch {
            print("Failed to save tokens: \(error)")
        }
    }
    
    private func loadTokens() {
        guard FileManager.default.fileExists(atPath: tokenPath.path) else { return }
        
        do {
            let data = try Data(contentsOf: tokenPath)
            let tokens = try JSONDecoder().decode(StoredTokens.self, from: data)
            self.accessToken = tokens.accessToken.isEmpty ? nil : tokens.accessToken
            self.refreshToken = tokens.refreshToken.isEmpty ? nil : tokens.refreshToken
            self.userEmail = tokens.userEmail.isEmpty ? nil : tokens.userEmail
            self.isAuthenticated = accessToken != nil
        } catch {
            print("Failed to load tokens: \(error)")
        }
    }
    
    private func deleteTokens() {
        try? FileManager.default.removeItem(at: tokenPath)
    }
}

// MARK: - Presentation Context Provider

class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Supporting Types

private struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct UserInfo: Codable {
    let email: String
    let name: String?
    let picture: String?
}

private struct StoredTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let userEmail: String
}

enum OAuthError: Error, LocalizedError {
    case noClientId
    case noRefreshToken
    case tokenRefreshFailed
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .noClientId:
            return "No Client ID configured"
        case .noRefreshToken:
            return "No refresh token. Please re-authenticate."
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}
