import Foundation
import SQLite3

/// Service for reading iMessage/SMS database using native SQLite3
class MessageDatabaseService {
    
    /// Path to the Messages database
    static let databasePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
    
    private var db: OpaquePointer?
    
    /// Serial queue for thread-safe database operations
    private let dbQueue = DispatchQueue(label: "com.macmessagebackup.messages.db", qos: .userInitiated)
    
    init() {
        // Defer connection to explicit call to prevent blocking initialization
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    /// Connect to the database
    func connect() {
        dbQueue.sync {
            guard db == nil else { return }
            
            let path = Self.databasePath.path
            
            guard FileManager.default.fileExists(atPath: path) else {
                print("⚠️ Messages database not found at: \(path)")
                print("💡 Make sure Full Disk Access is granted to this application")
                return
            }
            
            // Enable SQLite multi-thread mode for this connection
            let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
            if result == SQLITE_OK {
                print("✅ Connected to Messages database")
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("❌ Failed to connect to Messages database: \(errorMsg)")
                print("💡 Make sure Full Disk Access is granted in System Settings > Privacy & Security")
                db = nil
            }
        }
    }
    
    /// Check if database is accessible
    var isConnected: Bool {
        return db != nil
    }
    
    /// Fetch messages since a given row ID (for incremental backup)
    func fetchMessages(sinceRowId: Int64 = 0, limit: Int = 1000) throws -> [Message] {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        var messages: [Message] = []
        
        // Query includes attributedBody for newer macOS versions where text column is often NULL
        let query = """
            SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, 
                   COALESCE(h.id, 'Unknown') as handle_id, 
                   COALESCE(m.service, 'iMessage') as service,
                   m.cache_has_attachments,
                   m.attributedBody
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ?
            ORDER BY m.ROWID ASC
            LIMIT ?
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.invalidData
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, sinceRowId)
        let boundLimit = Int32(min(limit, Int(Int32.max)))
        sqlite3_bind_int(statement, 2, boundLimit)
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(statement, 0)
            let guid = String(cString: sqlite3_column_text(statement, 1))
            var text: String? = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let dateValue = sqlite3_column_int64(statement, 3)
            let isFromMe = sqlite3_column_int(statement, 4) == 1
            let handleId = String(cString: sqlite3_column_text(statement, 5))
            let service = String(cString: sqlite3_column_text(statement, 6))
            let hasAttachments = sqlite3_column_int(statement, 7) > 0
            
            // If text is nil or empty, try to extract from attributedBody (macOS Ventura+)
            if text == nil || text?.isEmpty == true {
                if let blobPointer = sqlite3_column_blob(statement, 8) {
                    let blobSize = sqlite3_column_bytes(statement, 8)
                    if blobSize > 0 {
                        let data = Data(bytes: blobPointer, count: Int(blobSize))
                        text = extractTextFromAttributedBody(data)
                    }
                }
            }
            
            let messageDate = convertAppleTimestamp(dateValue)
            
            let message = Message(
                id: rowId,
                guid: guid,
                text: text,
                date: messageDate,
                isFromMe: isFromMe,
                handleId: handleId,
                chatId: nil,
                service: service,
                hasAttachments: hasAttachments
            )
            messages.append(message)
        }
        
        return messages
    }
    
    /// Extract plain text from attributedBody blob (streamTyped data format used by macOS Messages)
    private func extractTextFromAttributedBody(_ data: Data) -> String? {
        // macOS Messages uses a special streamTyped format for attributedBody
        // The text is typically stored after specific markers
        
        // Method 1: Try NSKeyedUnarchiver with secure coding disabled
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            if let attributedString = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                return attributedString.string
            }
        } catch {
            // Continue to fallback methods
        }
        
        // Method 2: Look for the actual Chinese/UTF-8 text content in the blob
        // The streamTyped format has the string after specific byte patterns
        // Looking for sequences that indicate UTF-8 string content
        
        // Find all UTF-8 encoded Chinese text segments
        var extractedTexts: [String] = []
        var i = 0
        let bytes = [UInt8](data)
        
        while i < bytes.count {
            // Check for potential UTF-8 multi-byte sequence start
            if bytes[i] >= 0xE0 && bytes[i] <= 0xEF && i + 2 < bytes.count {
                // Potential 3-byte UTF-8 (Chinese characters are 3 bytes in UTF-8)
                var textStart = i
                var textEnd = i
                
                // Scan forward to find the extent of the UTF-8 text
                var j = i
                while j < bytes.count {
                    let byte = bytes[j]
                    if byte >= 0x20 && byte < 0x7F {
                        // ASCII printable
                        j += 1
                        textEnd = j
                    } else if byte >= 0xC0 && byte <= 0xDF && j + 1 < bytes.count {
                        // 2-byte UTF-8
                        j += 2
                        textEnd = j
                    } else if byte >= 0xE0 && byte <= 0xEF && j + 2 < bytes.count {
                        // 3-byte UTF-8 (Chinese)
                        j += 3
                        textEnd = j
                    } else if byte >= 0xF0 && byte <= 0xF7 && j + 3 < bytes.count {
                        // 4-byte UTF-8
                        j += 4
                        textEnd = j
                    } else if byte == 0x0A || byte == 0x0D {
                        // Newline, continue
                        j += 1
                        textEnd = j
                    } else {
                        break
                    }
                }
                
                if textEnd > textStart + 5 {
                    let textData = Data(bytes[textStart..<textEnd])
                    if let text = String(data: textData, encoding: .utf8) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count > 5 && !trimmed.hasPrefix("NS") && !trimmed.hasPrefix("bplist") {
                            extractedTexts.append(trimmed)
                        }
                    }
                }
                i = textEnd > i ? textEnd : i + 1
            } else {
                i += 1
            }
        }
        
        // Return the longest extracted text (most likely the actual message)
        if let longestText = extractedTexts.max(by: { $0.count < $1.count }) {
            return longestText
        }
        
        // Method 3: Try to find ASCII text patterns for English messages
        var longestAscii = ""
        var currentAscii = ""
        for byte in bytes {
            if byte >= 0x20 && byte < 0x7F {
                currentAscii.append(Character(UnicodeScalar(byte)))
            } else {
                if currentAscii.count > longestAscii.count && !currentAscii.hasPrefix("NS") && !currentAscii.hasPrefix("bplist") {
                    longestAscii = currentAscii
                }
                currentAscii = ""
            }
        }
        if currentAscii.count > longestAscii.count && !currentAscii.hasPrefix("NS") {
            longestAscii = currentAscii
        }
        
        return longestAscii.count > 10 ? longestAscii : nil
    }
    
    /// Get total message count, optionally filtering to only count messages after a specific row ID
    func getMessageCount(sinceRowId: Int64 = 0) throws -> Int {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        let query = sinceRowId > 0 
            ? "SELECT COUNT(*) FROM message WHERE ROWID > ?"
            : "SELECT COUNT(*) FROM message"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.invalidData
        }
        defer { sqlite3_finalize(statement) }
        
        if sinceRowId > 0 {
            sqlite3_bind_int64(statement, 1, sinceRowId)
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return 0
    }
    
    /// Get the latest message row ID
    func getLatestRowId() throws -> Int64 {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(ROWID) FROM message", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.invalidData
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        return 0
    }
    
    /// Convert Apple's timestamp format to Date
    private func convertAppleTimestamp(_ timestamp: Int64) -> Date {
        let seconds: TimeInterval
        if timestamp > 1_000_000_000_000 {
            seconds = TimeInterval(timestamp) / 1_000_000_000
        } else {
            seconds = TimeInterval(timestamp)
        }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}

/// Database errors
enum DatabaseError: Error, LocalizedError {
    case notConnected
    case accessDenied
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database not connected. Please grant Full Disk Access."
        case .accessDenied:
            return "Access denied. Please grant Full Disk Access in System Settings."
        case .invalidData:
            return "Invalid data format in database."
        }
    }
}
