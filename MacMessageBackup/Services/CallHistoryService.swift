import Foundation
import SQLite3

/// Service for reading Call History database using native SQLite3
class CallHistoryService {
    
    /// Path to the Call History database
    static let databasePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CallHistoryDB/CallHistory.storedata")
    
    private var db: OpaquePointer?
    
    /// Serial queue for thread-safe database operations
    private let dbQueue = DispatchQueue(label: "com.macmessagebackup.callhistory.db", qos: .userInitiated)
    
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
                print("⚠️ Call History database not found at: \(path)")
                print("💡 Make sure Full Disk Access is granted and you have call history")
                return
            }
            
            // Enable SQLite multi-thread mode for this connection
            let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
            if result == SQLITE_OK {
                print("✅ Connected to Call History database")
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("❌ Failed to connect to Call History database: \(errorMsg)")
                print("💡 Make sure Full Disk Access is granted in System Settings > Privacy & Security")
                db = nil
            }
        }
    }
    
    /// Check if database is accessible
    var isConnected: Bool {
        return db != nil
    }
    
    /// Fetch call records since a given row ID
    func fetchCallRecords(sinceRowId: Int64 = 0, limit: Int = 1000) throws -> [CallRecord] {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        var records: [CallRecord] = []
        
        let query = """
            SELECT Z_PK, ZADDRESS, ZDATE, ZDURATION, ZORIGINATED, ZANSWERED, ZREAD, ZSERVICE_PROVIDER
            FROM ZCALLRECORD
            WHERE Z_PK > ?
            ORDER BY Z_PK ASC
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
            let pk = sqlite3_column_int64(statement, 0)
            let address: String = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Unknown"
            let dateValue = sqlite3_column_double(statement, 2)
            let duration = sqlite3_column_double(statement, 3)
            let originated = sqlite3_column_int(statement, 4)
            let answered = sqlite3_column_int(statement, 5)
            let isRead = sqlite3_column_int(statement, 6) == 1
            let service: String = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "Phone"
            
            let callDate = Date(timeIntervalSinceReferenceDate: dateValue)
            let callType = determineCallType(originated: Int64(originated), answered: Int64(answered))
            
            let record = CallRecord(
                id: pk,
                address: address,
                date: callDate,
                duration: duration,
                callType: callType,
                isRead: isRead,
                service: service
            )
            records.append(record)
        }
        
        return records
    }
    
    /// Get total call record count, optionally filtering to only count records after a specific row ID
    func getRecordCount(sinceRowId: Int64 = 0) throws -> Int {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        let query = sinceRowId > 0 
            ? "SELECT COUNT(*) FROM ZCALLRECORD WHERE Z_PK > ?"
            : "SELECT COUNT(*) FROM ZCALLRECORD"
        
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
    
    /// Get the latest record row ID
    func getLatestRowId() throws -> Int64 {
        guard let db = db else {
            throw DatabaseError.notConnected
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(Z_PK) FROM ZCALLRECORD", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.invalidData
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        return 0
    }
    
    /// Determine call type from database fields
    private func determineCallType(originated: Int64, answered: Int64) -> CallType {
        if originated == 1 {
            return .outgoing
        }
        if answered == 1 {
            return .incoming
        }
        if originated == 0 && answered == 0 {
            return .missed
        }
        return .unknown
    }
}
