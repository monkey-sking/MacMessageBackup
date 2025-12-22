import Foundation

/// Type of phone call
enum CallType: Int, Codable, CustomStringConvertible {
    case incoming = 1
    case outgoing = 2
    case missed = 3
    case blocked = 4
    case unknown = 0
    
    var description: String {
        switch self {
        case .incoming: return String(localized: "Incoming")
        case .outgoing: return String(localized: "Outgoing")
        case .missed: return String(localized: "Missed")
        case .blocked: return String(localized: "Blocked")
        case .unknown: return String(localized: "Unknown")
        }
    }
    
    var emoji: String {
        switch self {
        case .incoming: return "📲"
        case .outgoing: return "📱"
        case .missed: return "📵"
        case .blocked: return "🚫"
        case .unknown: return "❓"
        }
    }
}

/// Represents a call record from FaceTime/Phone
struct CallRecord: Identifiable, Codable {
    let id: Int64
    let address: String      // Phone number
    let date: Date
    let duration: TimeInterval
    let callType: CallType
    let isRead: Bool
    let service: String      // FaceTime Audio, FaceTime Video, Phone
    
    enum CodingKeys: String, CodingKey {
        case id, address, date, duration, callType, isRead, service
        case dateFormatted, callTypeText, durationFormatted
    }
    
    // Custom encoding for better JSON output
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(address, forKey: .address)
        try container.encode(date.ISO8601Format(), forKey: .date)
        try container.encode(duration, forKey: .duration)
        try container.encode(callType.rawValue, forKey: .callType)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(service, forKey: .service)
        
        // Add human-readable fields
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try container.encode(formatter.string(from: date), forKey: .dateFormatted)
        try container.encode(callType.description, forKey: .callTypeText)
        try container.encode(formattedDuration, forKey: .durationFormatted)
    }
    
    // Custom decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        
        if let dateString = try? container.decode(String.self, forKey: .date) {
            date = ISO8601DateFormatter().date(from: dateString) ?? Date()
        } else {
            date = try container.decode(Date.self, forKey: .date)
        }
        
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        let callTypeRaw = try container.decode(Int.self, forKey: .callType)
        callType = CallType(rawValue: callTypeRaw) ?? .unknown
        isRead = try container.decode(Bool.self, forKey: .isRead)
        service = try container.decode(String.self, forKey: .service)
    }
    
    // Regular initializer
    init(id: Int64, address: String, date: Date, duration: TimeInterval, callType: CallType, isRead: Bool, service: String) {
        self.id = id
        self.address = address
        self.date = date
        self.duration = duration
        self.callType = callType
        self.isRead = isRead
        self.service = service
    }
    
    /// Formatted duration string
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Format for Gmail email body (similar to SMS Backup+)
    var emailBody: String {
        let callWord = String(localized: "call")
        let serviceWord = String(localized: "Service")
        let dateWord = String(localized: "Date")
        return """
        \(Int(duration))s (\(formattedDuration)) \(address) (\(callType.description) \(callWord))
        
        \(serviceWord): \(service)
        \(dateWord): \(formattedDate)
        """
    }
    
    /// Email subject
    var emailSubject: String {
        let toWord = String(localized: "to")
        let fromWord = String(localized: "from")
        let callWord = String(localized: "call")
        let direction = callType == .outgoing ? toWord : fromWord
        return "\(callType.emoji) \(callType.description) \(callWord) \(direction) \(address)"
    }
    
    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Calendar event title
    var calendarTitle: String {
        "\(callType.emoji) \(callType.description): \(address)"
    }
    
    /// Calendar event description
    var calendarDescription: String {
        let phoneWord = String(localized: "Phone")
        let typeWord = String(localized: "Type")
        let durationWord = String(localized: "Duration")
        let serviceWord = String(localized: "Service")
        return """
        \(phoneWord): \(address)
        \(typeWord): \(callType.description)
        \(durationWord): \(formattedDuration)
        \(serviceWord): \(service)
        """
    }
}
