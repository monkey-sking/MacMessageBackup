import Foundation

/// Preset format styles for email subjects and calendar titles
enum FormatPreset: String, Codable, CaseIterable {
    case chinese = "chinese"        // 中文格式: "联系人 - 短信", "号码（来电）"
    case english = "english"        // English: "SMS with Contact", "Number (incoming call)"
    case smsBackupPlus = "smsbackup" // SMS Backup+ style: "SMS with Contact", "Number (incoming call)"
    case compact = "compact"         // 简洁: "联系人", "号码 来电"
    
    var displayName: String {
        switch self {
        case .chinese: return String(localized: "Chinese Style")
        case .english: return String(localized: "English Style")
        case .smsBackupPlus: return String(localized: "SMS Backup+ Compatible")
        case .compact: return String(localized: "Compact Style")
        }
    }
    
    var smsSubject: String {
        switch self {
        case .chinese: return "{contact} - 短信"
        case .english: return "SMS with {contact}"
        case .smsBackupPlus: return "SMS with {contact}"
        case .compact: return "{contact}"
        }
    }
    
    var callSubject: String {
        switch self {
        case .chinese: return "{contact}（{type}）"
        case .english: return "{contact} ({type})"
        case .smsBackupPlus: return "{contact} ({type})"
        case .compact: return "{contact} {type}"
        }
    }
    
    var calendarTitle: String {
        switch self {
        case .chinese: return "{emoji} {type}: {contact}"
        case .english: return "{emoji} {type}: {contact}"
        case .smsBackupPlus: return "{emoji} {type}: {contact}"
        case .compact: return "{type}: {contact}"
        }
    }
    
    var callBody: String {
        switch self {
        case .chinese: return "{duration}s ({duration_formatted}) {contact}（{type}）"
        case .english: return "{duration}s ({duration_formatted}) {contact} ({type})"
        case .smsBackupPlus: return "{duration}s ({duration_formatted}) {contact} ({type})"
        case .compact: return "{contact} {type} {duration_formatted}"
        }
    }
}

/// Backup configuration settings
struct BackupConfig: Codable {
    // IMAP/Gmail settings
    var imapHost: String = "imap.gmail.com"
    var imapPort: Int = 993
    var smtpHost: String = "smtp.gmail.com"
    var smtpPort: Int = 465
    var email: String = ""
    var useSSL: Bool = true
    
    // Backup labels/folders
    var smsLabel: String = "SMS"
    var callLogLabel: String = "Call log"
    
    // Google Calendar settings
    var calendarSyncEnabled: Bool = true
    var calendarId: String = "primary"
    
    // Backup options
    var backupMessages: Bool = true
    var backupCallLog: Bool = true
    var autoBackupEnabled: Bool = false
    var autoBackupIntervalMinutes: Int = 60
    
    // Progress tracking
    var lastMessageBackupDate: Date?
    var lastCallLogBackupDate: Date?
    var lastMessageRowId: Int64 = 0
    var lastCallRecordRowId: Int64 = 0
    var lastCalendarSyncRowId: Int64 = 0
    
    // Email format settings
    var smsSubjectFormat: String = "{contact} - 短信"  // Default: "联系人 - 短信"
    var callSubjectFormat: String = "{contact}（{type}）"  // Default: "号码（来电）"
    var calendarTitleFormat: String = "{emoji} {type}: {contact}"  // Default: "📲 来电: 号码"
    var callBodyFormat: String = "{duration}s ({duration_formatted}) {contact}（{type}）"  // Call body format
    var useCustomFormat: Bool = false  // false = use preset, true = use custom
    var formatPreset: FormatPreset = .chinese  // Default preset
    
    // App appearance settings
    var hideDockIcon: Bool = false  // Hide app from Dock
    var showMenuBarIcon: Bool = true  // Show menu bar icon
    
    // File paths
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/MacMessageBackup/config.json")
    
    /// Save configuration to file
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(self)
        let directory = Self.configPath.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: Self.configPath)
    }
    
    /// Load configuration from file
    static func load() -> BackupConfig {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return BackupConfig()
        }
        
        do {
            let data = try Data(contentsOf: configPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BackupConfig.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
            return BackupConfig()
        }
    }
    
    // MARK: - Format Template Helpers
    
    /// Get the effective SMS subject format
    var effectiveSmsSubjectFormat: String {
        useCustomFormat ? smsSubjectFormat : formatPreset.smsSubject
    }
    
    /// Get the effective call subject format
    var effectiveCallSubjectFormat: String {
        useCustomFormat ? callSubjectFormat : formatPreset.callSubject
    }
    
    /// Get the effective calendar title format
    var effectiveCalendarTitleFormat: String {
        useCustomFormat ? calendarTitleFormat : formatPreset.calendarTitle
    }
    
    /// Clean up contact name by removing system suffixes like (filtered), (smsft_rm), etc.
    private func cleanContact(_ contact: String) -> String {
        var cleaned = contact
        // Remove common macOS Messages suffixes
        let suffixesToRemove = [
            "(filtered)", "(smsft_rm)", "(spam)", "(junk)",
            "(Filtered)", "(FILTERED)", "(Smsft_rm)", "(SMSFT_RM)"
        ]
        for suffix in suffixesToRemove {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "")
        }
        // Also remove any parenthetical suffix that looks like a filter tag
        if let range = cleaned.range(of: #"\([a-zA-Z_]+\)$"#, options: .regularExpression) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    /// Format SMS subject with placeholders replaced
    func formatSmsSubject(contact: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        let cleanedContact = cleanContact(contact)
        
        return effectiveSmsSubjectFormat
            .replacingOccurrences(of: "{contact}", with: cleanedContact)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
    }
    
    /// Format call subject with placeholders replaced
    func formatCallSubject(contact: String, type: String, duration: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        let cleanedContact = cleanContact(contact)
        
        return effectiveCallSubjectFormat
            .replacingOccurrences(of: "{contact}", with: cleanedContact)
            .replacingOccurrences(of: "{type}", with: type)
            .replacingOccurrences(of: "{duration}", with: duration)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
    }
    
    /// Format calendar title with placeholders replaced
    func formatCalendarTitle(contact: String, type: String, emoji: String) -> String {
        return effectiveCalendarTitleFormat
            .replacingOccurrences(of: "{contact}", with: contact)
            .replacingOccurrences(of: "{type}", with: type)
            .replacingOccurrences(of: "{emoji}", with: emoji)
    }
    
    /// Get the effective call body format
    var effectiveCallBodyFormat: String {
        useCustomFormat ? callBodyFormat : formatPreset.callBody
    }
    
    /// Format call body with placeholders replaced
    func formatCallBody(contact: String, type: String, duration: Int, durationFormatted: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        return effectiveCallBodyFormat
            .replacingOccurrences(of: "{contact}", with: contact)
            .replacingOccurrences(of: "{type}", with: type)
            .replacingOccurrences(of: "{duration}", with: String(duration))
            .replacingOccurrences(of: "{duration_formatted}", with: durationFormatted)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
    }
}
