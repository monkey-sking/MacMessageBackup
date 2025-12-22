import Foundation

/// Represents a message from iMessage/SMS database
struct Message: Identifiable, Codable {
    let id: Int64
    let guid: String
    let text: String?
    let date: Date
    let isFromMe: Bool
    let handleId: String  // Phone number or email
    let chatId: String?
    let service: String   // iMessage, SMS, etc.
    let hasAttachments: Bool
    
    // Custom date encoding key
    enum CodingKeys: String, CodingKey {
        case id, guid, text, date, isFromMe, handleId, chatId, service, hasAttachments
        case dateFormatted
    }
    
    // Custom encoding to output human-readable date
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(guid, forKey: .guid)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(date.ISO8601Format(), forKey: .date)
        try container.encode(isFromMe, forKey: .isFromMe)
        try container.encode(handleId, forKey: .handleId)
        try container.encodeIfPresent(chatId, forKey: .chatId)
        try container.encode(service, forKey: .service)
        try container.encode(hasAttachments, forKey: .hasAttachments)
        // Add human-readable date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try container.encode(formatter.string(from: date), forKey: .dateFormatted)
    }
    
    // Custom decoding to handle ISO date
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        guid = try container.decode(String.self, forKey: .guid)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        
        // Handle both ISO string and Date types
        if let dateString = try? container.decode(String.self, forKey: .date) {
            date = ISO8601DateFormatter().date(from: dateString) ?? Date()
        } else {
            date = try container.decode(Date.self, forKey: .date)
        }
        
        isFromMe = try container.decode(Bool.self, forKey: .isFromMe)
        handleId = try container.decode(String.self, forKey: .handleId)
        chatId = try container.decodeIfPresent(String.self, forKey: .chatId)
        service = try container.decode(String.self, forKey: .service)
        hasAttachments = try container.decode(Bool.self, forKey: .hasAttachments)
    }
    
    // Regular initializer
    init(id: Int64, guid: String, text: String?, date: Date, isFromMe: Bool, handleId: String, chatId: String?, service: String, hasAttachments: Bool) {
        self.id = id
        self.guid = guid
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
        self.handleId = handleId
        self.chatId = chatId
        self.service = service
        self.hasAttachments = hasAttachments
    }
    
    /// Format message for email body
    var emailBody: String {
        let direction = isFromMe ? "→" : "←"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        return """
        \(direction) \(isFromMe ? "To" : "From"): \(handleId)
        Date: \(dateFormatter.string(from: date))
        Service: \(service)
        
        \(text ?? "[No text content]")
        """
    }
    
    /// Email subject line
    var emailSubject: String {
        let prefix = isFromMe ? "SMS with" : "SMS from"
        return "\(prefix) \(handleId)"
    }
}

/// Represents a conversation/chat
struct Chat: Identifiable, Codable {
    let id: Int64
    let guid: String
    let identifier: String  // Phone number or group ID
    let displayName: String?
    let isGroup: Bool
}

/// Represents a contact handle (phone number or email)
struct Handle: Identifiable, Codable {
    let id: Int64
    let identifier: String  // Phone number or email
    let service: String     // iMessage, SMS
}
