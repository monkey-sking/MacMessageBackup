import Foundation

/// String extension for easy localization
extension String {
    /// Returns localized string
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    /// Returns localized string with arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

/// Localization helper
enum L10n {
    // MARK: - App
    enum App {
        static var title: String { "app.title".localized }
        
        enum Status {
            static var ready: String { "app.status.ready".localized }
            static var backingUp: String { "app.status.backing_up".localized }
            static var complete: String { "app.status.complete".localized }
            static var failed: String { "app.status.failed".localized }
        }
    }
    
    // MARK: - Database
    enum Database {
        enum Messages {
            static var connected: String { "database.messages.connected".localized }
            static var notConnected: String { "database.messages.not_connected".localized }
        }
        enum Calls {
            static var connected: String { "database.calls.connected".localized }
            static var notConnected: String { "database.calls.not_connected".localized }
        }
        static var grantAccess: String { "database.grant_access".localized }
    }
    
    // MARK: - Statistics
    enum Stats {
        static var messages: String { "stats.messages".localized }
        static var calls: String { "stats.calls".localized }
        static var total: String { "stats.total".localized }
        static var backedUp: String { "stats.backed_up".localized }
        static var pending: String { "stats.pending".localized }
    }
    
    // MARK: - Buttons
    enum Button {
        static var backupNow: String { "button.backup_now".localized }
        static var stop: String { "button.stop".localized }
        static var save: String { "button.save".localized }
        static var testConnection: String { "button.test_connection".localized }
        static var signInGoogle: String { "button.sign_in_google".localized }
        static var signOut: String { "button.sign_out".localized }
        static var reset: String { "button.reset".localized }
        static var cancel: String { "button.cancel".localized }
    }
    
    // MARK: - Settings
    enum Settings {
        static var title: String { "settings.title".localized }
        static var gmail: String { "settings.gmail".localized }
        static var backup: String { "settings.backup".localized }
        static var advanced: String { "settings.advanced".localized }
        static var about: String { "settings.about".localized }
        
        enum Gmail {
            static var authMethod: String { "settings.gmail.auth_method".localized }
            static var oauth: String { "settings.gmail.oauth".localized }
            static var appPassword: String { "settings.gmail.app_password".localized }
            static var email: String { "settings.gmail.email".localized }
            static var password: String { "settings.gmail.password".localized }
            static var passwordHint: String { "settings.gmail.password_hint".localized }
            static var createPassword: String { "settings.gmail.create_password".localized }
            static var clientId: String { "settings.gmail.client_id".localized }
            static var clientSecret: String { "settings.gmail.client_secret".localized }
            static var connected: String { "settings.gmail.connected".localized }
            static var notConnected: String { "settings.gmail.not_connected".localized }
        }
        
        enum Labels {
            static var sms: String { "settings.labels.sms".localized }
            static var callLog: String { "settings.labels.call_log".localized }
        }
        
        enum Backup {
            static var messages: String { "settings.backup.messages".localized }
            static var callLog: String { "settings.backup.call_log".localized }
            static var calendarSync: String { "settings.backup.calendar_sync".localized }
            static var autoEnabled: String { "settings.backup.auto_enabled".localized }
            static var interval: String { "settings.backup.interval".localized }
        }
    }
    
    // MARK: - Menu
    enum Menu {
        static var backupNow: String { "menu.backup_now".localized }
        static var autoBackup: String { "menu.auto_backup".localized }
        static var settings: String { "menu.settings".localized }
        static var quit: String { "menu.quit".localized }
    }
    
    // MARK: - Call Types
    enum Call {
        static var incoming: String { "call.incoming".localized }
        static var outgoing: String { "call.outgoing".localized }
        static var missed: String { "call.missed".localized }
        static var blocked: String { "call.blocked".localized }
        static var unknown: String { "call.unknown".localized }
    }
    
    // MARK: - Results
    enum Result {
        static func messagesBackedUp(_ count: Int) -> String {
            "result.messages_backed_up".localized(with: count)
        }
        static func callsBackedUp(_ count: Int) -> String {
            "result.calls_backed_up".localized(with: count)
        }
        static func calendarSynced(_ count: Int) -> String {
            "result.calendar_synced".localized(with: count)
        }
        static var nothingNew: String { "result.nothing_new".localized }
    }
}
