import Foundation

/// Service for syncing call records to Google Calendar
/// Note: This implementation uses direct REST API calls instead of Google's SDK
/// for simpler dependency management
class GoogleCalendarService {
    
    private var accessToken: String?
    private var refreshToken: String?
    private let config: BackupConfig
    
    // OAuth configuration - User needs to create these in Google Cloud Console
    private let clientId: String
    private let clientSecret: String
    private let redirectUri = "http://localhost:8080/callback"
    private let scope = "https://www.googleapis.com/auth/calendar.events"
    
    init(config: BackupConfig, clientId: String = "", clientSecret: String = "") {
        self.config = config
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    
    /// Generate OAuth authorization URL
    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }
    
    /// Exchange authorization code for tokens
    func exchangeCodeForTokens(_ code: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CalendarError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        
        // Save refresh token for later use
        try saveRefreshToken(tokenResponse.refreshToken ?? "")
    }
    
    /// Refresh access token
    func refreshAccessToken() async throws {
        guard let refreshToken = try loadRefreshToken() else {
            throw CalendarError.noRefreshToken
        }
        
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
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
            throw CalendarError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
    }
    
    /// Create a calendar event for a call record
    func createCallEvent(_ record: CallRecord) async throws {
        if accessToken == nil {
            try await refreshAccessToken()
        }
        
        guard let token = self.accessToken else {
            throw CalendarError.noAccessToken
        }
        
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(config.calendarId)/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create event
        let endDate = record.date.addingTimeInterval(max(record.duration, 60)) // At least 1 minute
        let dateFormatter = ISO8601DateFormatter()
        
        let event: [String: Any] = [
            "summary": record.calendarTitle,
            "description": record.calendarDescription,
            "start": [
                "dateTime": dateFormatter.string(from: record.date),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": dateFormatter.string(from: endDate),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: event)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.createEventFailed
        }
    }
    
    /// Create events for multiple call records
    func createCallEvents(_ records: [CallRecord], progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        for (index, record) in records.enumerated() {
            try await createCallEvent(record)
            progressHandler?(index + 1, records.count)
            
            // Rate limiting
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
    }
    
    // MARK: - Token Storage
    
    private let tokenPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/MacMessageBackup/gcal_token")
    
    private func saveRefreshToken(_ token: String) throws {
        let directory = tokenPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try token.write(to: tokenPath, atomically: true, encoding: .utf8)
    }
    
    private func loadRefreshToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenPath.path) else {
            return nil
        }
        return try String(contentsOf: tokenPath, encoding: .utf8)
    }
}

// MARK: - Supporting Types

struct TokenResponse: Codable {
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

enum CalendarError: Error, LocalizedError {
    case noAccessToken
    case noRefreshToken
    case authenticationFailed
    case tokenRefreshFailed
    case createEventFailed
    
    var errorDescription: String? {
        switch self {
        case .noAccessToken:
            return "No access token. Please authenticate with Google Calendar."
        case .noRefreshToken:
            return "No refresh token. Please re-authenticate with Google Calendar."
        case .authenticationFailed:
            return "Google Calendar authentication failed."
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please re-authenticate."
        case .createEventFailed:
            return "Failed to create calendar event."
        }
    }
}
