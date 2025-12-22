import Foundation
import Security

/// Service for backing up to Gmail via SMTP
class IMAPService {
    
    private var config: BackupConfig
    private var cachedPassword: String? // In-memory cache to avoid repeated Keychain prompts
    
    init(config: BackupConfig) {
        self.config = config
    }
    
    // MARK: - Keychain Operations
    
    /// Check if password exists in Keychain for current email
    var hasPassword: Bool {
        if cachedPassword != nil { return true }
        guard !config.email.isEmpty else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: config.email, // Use email as account
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Store password securely in Keychain
    func savePassword(_ password: String) throws {
        guard !config.email.isEmpty else { return }
        
        cachedPassword = password // Update cache
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: config.email,
            kSecValueData as String: password.data(using: .utf8)!
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw IMAPError.authenticationFailed
        }
        
        // Also cleanup old generic password if it exists (migration cleanup)
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: "gmail_app_password"
        ]
        SecItemDelete(oldQuery as CFDictionary)
    }
    
    /// Retrieve password from Keychain
    func getPassword() throws -> String? {
        if let cached = cachedPassword { return cached }
        guard !config.email.isEmpty else { return nil }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: config.email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            let password = String(data: data, encoding: .utf8)
            cachedPassword = password // Populate cache
            return password
        }
        
        // Fallback: Check for old generic password (migration support)
        // If found, we should migrate it, but read-only for now is safer until next save
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: "gmail_app_password",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var oldResult: AnyObject?
        let oldStatus = SecItemCopyMatching(oldQuery as CFDictionary, &oldResult)
        
        if oldStatus == errSecSuccess, let oldData = oldResult as? Data {
            let password = String(data: oldData, encoding: .utf8)
            // Do not cache old password as we want it migrated eventually
            return password
        }
        
        return nil
    }
    
    /// Delete stored password
    func deletePassword() throws {
        cachedPassword = nil
        guard !config.email.isEmpty else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macmessagebackup",
            kSecAttrAccount as String: config.email
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Gmail API Backup (using REST API)
    
    /// Backup messages to Gmail using Gmail API
    /// progressHandler receives (current, total, lastSuccessfulMessageId)
    /// Backup messages to Gmail using Gmail API or Batch IMAP
    /// progressHandler receives (current, total, lastSuccessfulMessageId)
    func backupMessages(_ messages: [Message], progressHandler: ((Int, Int, Int64) -> Void)? = nil) async throws {
        guard let password = try getPassword(), !password.isEmpty else {
            throw IMAPError.noPassword
        }
        
        // Create backup directory for local copies and temp emls
        let backupDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/backups")
        let emlDir = FileManager.default.temporaryDirectory.appendingPathComponent("batch_emls_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)
        
        var batchItems: [(path: String, date: Date, id: Int64)] = []
        
        print("Prepare batch files for \(messages.count) messages...")
        
        // Phase 1: Create all .eml files locally
        for message in messages {
            // Local JSON backup
            let filename = "msg_\(message.id)_\(Int(message.date.timeIntervalSince1970)).json"
            let filePath = backupDir.appendingPathComponent(filename)
            if let data = try? JSONEncoder().encode(message) {
                try? data.write(to: filePath)
            }
            
            // Create EML
            let emailContent = createEmailContent(for: message)
            let emlName = "msg_\(message.id).eml"
            let emlPath = emlDir.appendingPathComponent(emlName)
            
            try emailContent.write(to: emlPath, atomically: true, encoding: .utf8)
            batchItems.append((path: emlPath.path, date: message.date, id: message.id))
        }
        
        print("Starting batch upload worker...")
        
        // Phase 2: Run batch worker
        // Note: For very large sets, we might want to slice this, but Int.max means "all".
        // Let's process in chunks of 500 to keep the Python pipe responsive and not overwhelm memory/args?
        // Actually we feed via stdin so args isn't an issue.
        // But let's stick to processing all at once with the worker to keep connection open.
        
        try await runBatchWorker(items: batchItems, mailbox: config.smsLabel, progressHandler: progressHandler)
        
        // Cleanup temp dir
        try? FileManager.default.removeItem(at: emlDir)
        
        print("✅ Backed up messages batch complete")
    }
    
    /// Backup call records
    /// progressHandler receives (current, total, lastSuccessfulRecordId)
    /// Backup call records
    /// progressHandler receives (current, total, lastSuccessfulRecordId)
    func backupCallRecords(_ records: [CallRecord], progressHandler: ((Int, Int, Int64) -> Void)? = nil) async throws {
        guard let password = try getPassword(), !password.isEmpty else {
            throw IMAPError.noPassword
        }
        
        let backupDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/backups")
        let emlDir = FileManager.default.temporaryDirectory.appendingPathComponent("batch_emls_call_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)
        
        var batchItems: [(path: String, date: Date, id: Int64)] = []
        
        print("Prepare batch files for \(records.count) call records...")
        
        for record in records {
            let filename = "call_\(record.id)_\(Int(record.date.timeIntervalSince1970)).json"
            let filePath = backupDir.appendingPathComponent(filename)
            if let data = try? JSONEncoder().encode(record) {
                try? data.write(to: filePath)
            }
            
            let emailContent = createEmailContent(for: record)
            let emlName = "call_\(record.id).eml"
            let emlPath = emlDir.appendingPathComponent(emlName)
            
            try emailContent.write(to: emlPath, atomically: true, encoding: .utf8)
            batchItems.append((path: emlPath.path, date: record.date, id: record.id))
        }
        
        print("Starting batch upload worker for calls...")
        
        try await runBatchWorker(items: batchItems, mailbox: config.callLogLabel, progressHandler: progressHandler)
        
        try? FileManager.default.removeItem(at: emlDir)
        
        print("✅ Backed up call records batch complete")
    }
    
    /// Append message to Gmail using IMAP APPEND (like SMS Backup+)
    private func appendToGmailDraft(message: Message) async throws {
        // Create RFC 2822 email format
        let emailContent = createEmailContent(for: message)
        
        // Try OAuth Gmail API first
        if let token = await getOAuthToken() {
            try await sendToGmailAPI(emailContent: emailContent, token: token, label: config.smsLabel)
            return
        }
        
        // Use IMAP APPEND with App Password (works through proxies!)
        if let password = try? getPassword(), !password.isEmpty, !config.email.isEmpty {
            try await sendViaIMAP(emailContent: emailContent, password: password, mailbox: config.smsLabel, eventDate: message.date)
            return
        }
        
        // Fallback: Save as .eml file for manual import
        let emlDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/gmail_drafts")
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)
        
        let emlFile = emlDir.appendingPathComponent("msg_\(message.id).eml")
        try emailContent.write(to: emlFile, atomically: true, encoding: .utf8)
    }
    
    /// Append call record to Gmail using IMAP APPEND (like SMS Backup+)
    private func appendCallRecordToGmail(record: CallRecord) async throws {
        let emailContent = createEmailContent(for: record)
        
        // Try OAuth Gmail API first
        if let token = await getOAuthToken() {
            try await sendToGmailAPI(emailContent: emailContent, token: token, label: config.callLogLabel)
            return
        }
        
        // Use IMAP APPEND with App Password (works through proxies!)
        if let password = try? getPassword(), !password.isEmpty, !config.email.isEmpty {
            try await sendViaIMAP(emailContent: emailContent, password: password, mailbox: config.callLogLabel, eventDate: record.date)
            return
        }
        
        // Fallback: Save as .eml file
        let emlDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/gmail_drafts")
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)
        
        let emlFile = emlDir.appendingPathComponent("call_\(record.id).eml")
        try emailContent.write(to: emlFile, atomically: true, encoding: .utf8)
    }
    
    /// Send email via IMAP APPEND using App Password (works through proxies!)
    private func sendViaIMAP(emailContent: String, password: String, mailbox: String, eventDate: Date? = nil) async throws {
        // Use Python script to append via IMAP
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/imap_append.py")
        
        // Create the Python IMAP script if it doesn't exist
        try createIMAPScript(at: scriptPath)
        
        // Write email content to temp file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("email_\(UUID().uuidString).eml")
        try emailContent.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Calculate timestamp for IMAP (use event date or current date)
        let timestamp = Int((eventDate ?? Date()).timeIntervalSince1970)
        
        // Run Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath.path, config.email, password.replacingOccurrences(of: " ", with: ""), tempFile.path, mailbox, String(timestamp)]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempFile)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw IMAPError.sendFailed(output)
        }
        
        print("✅ Email appended via IMAP successfully")
    }
    
    /// Create Python IMAP APPEND script with auto-create label support
    private func createIMAPScript(at path: URL) throws {
        let script = """
        #!/usr/bin/env python3
        import sys
        import imaplib
        import ssl
        import time
        
        def main():
            if len(sys.argv) < 5:
                print("Usage: imap_append.py <email> <password> <eml_file> <mailbox> [timestamp]")
                sys.exit(1)
            
            email = sys.argv[1]
            password = sys.argv[2]
            eml_file = sys.argv[3]
            mailbox = sys.argv[4]
            
            # Use provided timestamp or current time
            if len(sys.argv) >= 6:
                try:
                    event_time = int(sys.argv[5])
                except ValueError:
                    event_time = int(time.time())
            else:
                event_time = int(time.time())
            
            # Quote mailbox name if it contains spaces (for IMAP compatibility)
            quoted_mailbox = f'"{mailbox}"' if ' ' in mailbox else mailbox
            
            with open(eml_file, 'r') as f:
                message = f.read()
            
            try:
                context = ssl.create_default_context()
                imap = imaplib.IMAP4_SSL('imap.gmail.com', 993, ssl_context=context)
                imap.login(email, password)
                print(f"Logged in as {email}")
                
                # Try to select the mailbox, if it fails, create it (like SMS Backup+)
                status, _ = imap.select(quoted_mailbox)
                if status != 'OK':
                    # Mailbox doesn't exist, create it
                    result = imap.create(quoted_mailbox)
                    print(f"Created label '{mailbox}': {result}")
                else:
                    imap.close()
                
                # Append the message with actual event time
                result = imap.append(quoted_mailbox, None, imaplib.Time2Internaldate(event_time), message.encode('utf-8'))
                
                if result[0] == 'OK':
                    print(f"Message appended successfully to '{mailbox}'")
                else:
                    print(f"Append failed: {result}")
                    sys.exit(1)
                
                imap.logout()
            except Exception as e:
                print(f"Error: {e}")
                sys.exit(1)
        
        if __name__ == "__main__":
            main()
        """
        
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: path, atomically: true, encoding: .utf8)
        
        // Make script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    
    /// Get OAuth token from GoogleOAuthService
    private func getOAuthToken() async -> String? {
        // Try to load from saved tokens file
        let tokenPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/oauth_tokens.json")
        
        guard FileManager.default.fileExists(atPath: tokenPath.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: tokenPath)
            let tokens = try JSONDecoder().decode(StoredTokensDTO.self, from: data)
            if !tokens.accessToken.isEmpty {
                return tokens.accessToken
            }
        } catch {
            print("Failed to load OAuth tokens: \(error)")
        }
        return nil
    }
    
    /// Send email to Gmail using Gmail API
    private func sendToGmailAPI(emailContent: String, token: String, label: String) async throws {
        // Gmail API endpoint to insert message
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?internalDateSource=dateHeader")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Base64url encode the email content
        let base64Email = emailContent.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // Create request body with label
        let body: [String: Any] = [
            "raw": base64Email,
            "labelIds": ["INBOX", label]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IMAPError.sendFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            print("✅ Email sent to Gmail successfully")
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Gmail API error: \(httpResponse.statusCode) - \(errorBody)")
            throw IMAPError.sendFailed("Status \(httpResponse.statusCode): \(errorBody)")
        }
    }
    
    /// DTO for reading stored tokens
    private struct StoredTokensDTO: Codable {
        let accessToken: String
        let refreshToken: String
        let userEmail: String
    }
    
    /// Create RFC 2822 email content for message (SMS Backup+ compatible format)
    private func createEmailContent(for message: Message) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        
        // Clean the contact ID by removing (filtered), (smsft_rm) etc.
        let cleanedHandleId = cleanContact(message.handleId)
        
        // Use configurable subject format
        let subject = config.formatSmsSubject(contact: cleanedHandleId, date: message.date)
        
        // From field: Use the cleaned phone number for threading like SMS Backup+
        let fromField = message.isFromMe ? config.email : "\(cleanedHandleId) <\(cleanedHandleId)@sms.mac.backup>"
        
        // Message body - use text or indicate it's an attachment/empty message
        let body: String
        if let text = message.text, !text.isEmpty {
            body = text
        } else if message.hasAttachments {
            body = String(localized: "[Attachment]")
        } else {
            body = String(localized: "[No text content]")
        }
        
        return """
        From: \(fromField)
        To: \(config.email)
        Subject: \(subject)
        Date: \(dateFormatter.string(from: message.date))
        Content-Type: text/plain; charset=UTF-8
        X-smssync-address: \(cleanedHandleId)
        X-smssync-datatype: sms
        X-smssync-backup-time: \(Int(Date().timeIntervalSince1970 * 1000))
        
        \(body)
        """
    }
    
    /// Clean contact name by removing system suffixes like (filtered), (smsft_rm), etc.
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
    
    /// Create RFC 2822 email content for call record (SMS Backup+ compatible format)
    private func createEmailContent(for record: CallRecord) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        
        // Localized call type
        let typeText: String
        switch record.callType {
        case .incoming: typeText = String(localized: "incoming call")
        case .outgoing: typeText = String(localized: "outgoing call")
        case .missed: typeText = String(localized: "missed call")
        case .blocked: typeText = String(localized: "blocked call")
        case .unknown: typeText = String(localized: "call")
        }
        
        let duration = Int(record.duration)
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        let durationFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Use configurable subject format
        let subject = config.formatCallSubject(contact: record.address, type: typeText, duration: durationFormatted, date: record.date)
        
        // Use configurable body format
        let body = config.formatCallBody(contact: record.address, type: typeText, duration: duration, durationFormatted: durationFormatted, date: record.date)
        
        return """
        From: \(record.address) <\(record.address)@call.log.mac.backup>
        To: \(config.email)
        Subject: \(subject)
        Date: \(dateFormatter.string(from: record.date))
        Content-Type: text/plain; charset=UTF-8
        X-smssync-address: \(record.address)
        X-smssync-datatype: calllog
        X-smssync-backup-time: \(Int(Date().timeIntervalSince1970 * 1000))
        
        \(body)
        """
    }
    
    /// Test connection (check if credentials are valid via real IMAP login)
    func testConnection() async throws -> Bool {
        guard let password = try getPassword(), !password.isEmpty else {
            throw IMAPError.noPassword
        }
        
        guard !config.email.isEmpty else {
            throw IMAPError.connectionFailed
        }
        
        // Use Python script to test connection
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/imap_test.py")
        
        // Create the Python IMAP test script
        try createIMAPTestScript(at: scriptPath)
        
        // Run Python script to test login (pass password via stdin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // Only pass email as arg, password via stdin
        process.arguments = [scriptPath.path, config.email]
        
        let pipe = Pipe()
        let inputPipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = inputPipe
        
        try process.run()
        
        // Write password to stdin
        // NOTE: We do NOT strip spaces here automatically. Google App Passwords
        // work with spaces in the web UI, but standard IMAP might expect them removed.
        // However, user might have stripped them or not.
        // Best practice: Try as-is. If user copy-pastes "abcd efgh", we send that.
        // Actually, for IMAP protocols, usually spaces are removed.
        // Let's strip spaces just to be safe as that's standard for App Passwords.
        let sanitizedPassword = password.replacingOccurrences(of: " ", with: "")
        if let data = (sanitizedPassword + "\n").data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try? inputPipe.fileHandleForWriting.close()
        }
        
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus == 0 {
            print("✅ Gmail connection test passed")
            return true
        } else {
            print("❌ Gmail connection test failed: \(output)")
            return false
        }
    }
    
    /// Create Python IMAP Test script
    private func createIMAPTestScript(at path: URL) throws {
        let script = """
        #!/usr/bin/env python3
        import sys
        import imaplib
        import ssl
        
        def main():
            if len(sys.argv) != 2:
                sys.stderr.write("Usage: imap_test.py <email> (password from stdin)\\n")
                sys.exit(1)
            
            email = sys.argv[1]
            sys.stderr.write(f"Testing connection for: {email}\\n")
            
            # Read password from stdin
            try:
                password = sys.stdin.readline().strip()
                if not password:
                    sys.stderr.write("Error: Empty password received from stdin\\n")
                    sys.exit(1)
            except Exception as e:
                sys.stderr.write(f"Error reading stdin: {e}\\n")
                sys.exit(1)
            
            try:
                sys.stderr.write("Connecting to imap.gmail.com:993...\\n")
                context = ssl.create_default_context()
                imap = imaplib.IMAP4_SSL('imap.gmail.com', 993, ssl_context=context)
                
                sys.stderr.write("Logging in...\\n")
                imap.login(email, password)
                
                sys.stderr.write("Login successful. Logging out...\\n")
                imap.logout()
                sys.exit(0)
            except Exception as e:
                sys.stderr.write(f"IMAP Error: {e}\\n")
                sys.exit(1)
        
        if __name__ == "__main__":
            main()
        """
        
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    /// Create Python Batch IMAP script
    private func createBatchIMAPScript(at path: URL) throws {
        let script = """
        #!/usr/bin/env python3
        import sys
        import imaplib
        import ssl
        import time
        import os
        
        def main():
            # Expected args: email, password, mailbox
            if len(sys.argv) < 4:
                print("Usage: imap_batch.py <email> <password> <mailbox>")
                sys.exit(1)
            
            email = sys.argv[1]
            password = sys.argv[2]
            mailbox = sys.argv[3]
            
            # Flush stdout immediately
            sys.stdout.reconfigure(line_buffering=True)
            
            try:
                # print(f"Connecting to Gmail...")
                context = ssl.create_default_context()
                imap = imaplib.IMAP4_SSL('imap.gmail.com', 993, ssl_context=context)
                imap.login(email, password)
                
                quoted_mailbox = f'"{mailbox}"' if ' ' in mailbox else mailbox
                status, _ = imap.select(quoted_mailbox)
                if status != 'OK':
                    imap.create(quoted_mailbox)
                    imap.select(quoted_mailbox)
                    
                print("READY")
                
                # Read lines from stdin: file_path|timestamp|id
                for line in sys.stdin:
                    line = line.strip()
                    if not line: continue
                    
                    try:
                        parts = line.split('|')
                        if len(parts) < 3:
                            print(f"ERROR:0:Invalid input format")
                            continue
                            
                        file_path = parts[0]
                        timestamp_str = parts[1]
                        id_str = parts[2]
                        
                        if not os.path.exists(file_path):
                            print(f"ERROR:{id_str}:File not found")
                            continue
                            
                        with open(file_path, 'r') as f:
                            content = f.read()
                        
                        timestamp = int(timestamp_str)
                        result = imap.append(quoted_mailbox, None, imaplib.Time2Internaldate(timestamp), content.encode('utf-8'))
                        
                        if result[0] == 'OK':
                            print(f"SUCCESS:{id_str}")
                            # Clean up file
                            try:
                                os.remove(file_path)
                            except:
                                pass
                        else:
                            print(f"ERROR:{id_str}:Append failed {result}")
                            
                    except Exception as e:
                        # try to parse id if possible
                        try:
                            parts = line.split('|')
                            err_id = parts[2]
                        except:
                            err_id = "0"
                        print(f"ERROR:{err_id}:{str(e)}")
                
                try:
                    imap.logout()
                except:
                    pass
                
            except Exception as e:
                print(f"FATAL:{str(e)}")
                sys.exit(1)
        
        if __name__ == "__main__":
            main()
        """
        
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    
    /// Run batch worker
    /// progressHandler: (current, total, id)
    private func runBatchWorker(items: [(path: String, date: Date, id: Int64)], mailbox: String, progressHandler: ((Int, Int, Int64) -> Void)?) async throws {
        guard let password = try getPassword(), !password.isEmpty else {
            throw IMAPError.noPassword
        }
        
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/imap_batch.py")
        
        try createBatchIMAPScript(at: scriptPath)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath.path, config.email, password.replacingOccurrences(of: " ", with: ""), mailbox]
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var completedCount = 0
        let totalCount = items.count
        
        // Output handler
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                if line.hasPrefix("SUCCESS:") {
                    let parts = line.split(separator: ":")
                    if parts.count >= 2, let id = Int64(parts[1]) {
                        completedCount += 1
                        progressHandler?(completedCount, totalCount, id)
                    }
                } else if line.hasPrefix("READY") {
                    // Ready to accept input
                } else if line.hasPrefix("FATAL:") {
                    print("Batch worker fatal error: \(line)")
                } else {
                     // print("Worker output: \(line)")
                }
            }
        }
        
        try process.run()
        
        // Feed input
        let fileHandle = inputPipe.fileHandleForWriting
        for item in items {
            let timestamp = Int(item.date.timeIntervalSince1970)
            let line = "\(item.path)|\(timestamp)|\(item.id)\n"
            if let data = line.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
        }
        try fileHandle.close()
        
        process.waitUntilExit()
        
        // Clean up readability handler
        outputPipe.fileHandleForReading.readabilityHandler = nil
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("Batch worker exited with error: \(errorMsg)")
            // If some succeeded, we don't throw, but log warning.
            // But if 0 succeeded, we throw.
            if completedCount == 0 {
                throw IMAPError.sendFailed("Batch worker failed: \(errorMsg)")
            }
        }
    }
}

/// IMAP service errors
enum IMAPError: Error, LocalizedError {
    case noPassword
    case connectionFailed
    case authenticationFailed
    case sendFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noPassword:
            return "No password configured. Please set your Gmail App Password."
        case .connectionFailed:
            return "Failed to connect to mail server."
        case .authenticationFailed:
            return "Authentication failed. Check your email and password."
        case .sendFailed(let message):
            return "Failed to send email: \(message)"
        }
    }
}
