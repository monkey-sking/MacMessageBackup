import SwiftUI

/// 重新设计的设置视图 - 简洁清晰，完全中文化
/// Uses native macOS components (TabView, Form) for a polished look.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var oauthService = GoogleOAuthService()
    @ObservedObject private var localCalendarService = LocalCalendarService.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var testingConnection = false
    @State private var connectionResult: String?
    @State private var selectedTab: Int = 0
    
    // Initial tab can be passed in, but we use @State for the TabView selection
    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            gmailSettingsTab
                .tabItem {
                    Label(String(localized: "Gmail"), systemImage: "envelope.fill")
                }
                .tag(0)
            
            backupSettingsTab
                .tabItem {
                    Label(String(localized: "Backup"), systemImage: "arrow.clockwise.circle.fill")
                }
                .tag(1)
            
            advancedSettingsTab
                .tabItem {
                    Label(String(localized: "Advanced"), systemImage: "gearshape.fill")
                }
                .tag(2) // Moved appearance/format here
                
            aboutTab
                .tabItem {
                    Label(String(localized: "About"), systemImage: "info.circle.fill")
                }
                .tag(3)
        }
        .frame(width: 500, height: 550) // Standard macOS settings size
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
        .onAppear {
            email = appState.config.email
            // Do NOT pre-fill password to avoid Keychain prompt loops
        }
    }
    
    // MARK: - Tabs
    
    var gmailSettingsTab: some View {
        Form {
            Section {
                HStack {
                    if appState.gmailConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(String(localized: "Gmail Connected"))
                                .font(.headline)
                            if !email.isEmpty {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(String(localized: "Gmail Not Connected"))
                                .font(.headline)
                            Text(String(localized: "Please enter your credentials below."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section(String(localized: "Account Info")) {
                TextField(String(localized: "Email"), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                
                SecureField(String(localized: "App Password"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                
                Text(String(localized: "Use a Gmail App Password, not your regular password."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Link(String(localized: "How to create an App Password"),
                     destination: URL(string: "https://support.google.com/accounts/answer/185833")!)
                    .font(.caption)
            }
            
            Section(String(localized: "Backup Labels")) {
                TextField(String(localized: "SMS Label"), text: Binding(
                    get: { appState.config.smsLabel },
                    set: { appState.config.smsLabel = $0 }
                ))
                
                TextField(String(localized: "Call Log Label"), text: Binding(
                    get: { appState.config.callLogLabel },
                    set: { appState.config.callLogLabel = $0 }
                ))
            }
            
            Section {
                HStack {
                    Button(action: testConnection) {
                        HStack {
                            if testingConnection {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(String(localized: "Test Connection"))
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || testingConnection)
                    
                    Spacer()
                    
                    Button(String(localized: "Save Settings")) {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty)
                }
                
                if let result = connectionResult {
                    HStack {
                        Image(systemName: result.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.contains("✅") ? .green : .red)
                        Text(result)
                            .font(.body)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    var backupSettingsTab: some View {
        Form {
            Section(String(localized: "Backup Options")) {
                Toggle(String(localized: "Backup Messages to Gmail"), isOn: Binding(
                    get: { appState.config.backupMessages },
                    set: {
                        appState.config.backupMessages = $0
                        appState.saveConfig()
                    }
                ))
                
                Toggle(String(localized: "Backup Call Log to Gmail"), isOn: Binding(
                    get: { appState.config.backupCallLog },
                    set: {
                        appState.config.backupCallLog = $0
                        appState.saveConfig()
                    }
                ))
                
                Toggle(isOn: Binding(
                    get: { appState.config.markBackupAsRead },
                    set: {
                        appState.config.markBackupAsRead = $0
                        appState.saveConfig()
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "Mark backup as read"))
                        Text(String(localized: "Mark backed up messages as read in Gmail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section(String(localized: "Calendar Backup")) {
                Toggle(String(localized: "Backup Call Log to Calendar"), isOn: Binding(
                    get: { appState.config.calendarSyncEnabled },
                    set: {
                        appState.config.calendarSyncEnabled = $0
                        appState.saveConfig()
                    }
                ))
                
                if appState.config.calendarSyncEnabled {
                    if !localCalendarService.isAuthorized {
                        HStack {
                            Text(String(localized: "Permission required"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(String(localized: "Connect Calendar")) {
                                Task {
                                    _ = await localCalendarService.requestAccess()
                                }
                            }
                        }
                    } else {
                        Picker(String(localized: "Select Calendar"), selection: Binding(
                            get: { appState.config.calendarId },
                            set: {
                                appState.config.calendarId = $0
                                appState.saveConfig()
                            }
                        )) {
                            Text(String(localized: "Select a calendar")).tag("primary")
                            ForEach(localCalendarService.availableCalendars, id: \.calendarIdentifier) { calendar in
                                Text(calendar.title).tag(calendar.calendarIdentifier)
                            }
                        }
                    }
                }
            }
            
            Section(String(localized: "Auto Backup")) {
                Toggle(String(localized: "Enable Auto Backup"), isOn: Binding(
                    get: { appState.config.autoBackupEnabled },
                    set: {
                        appState.config.autoBackupEnabled = $0
                        appState.saveConfig()
                        if $0 {
                            appState.scheduler?.startAutoBackup()
                        } else {
                            appState.scheduler?.stopAutoBackup()
                        }
                    }
                ))
                
                if appState.config.autoBackupEnabled {
                    Picker(String(localized: "Backup Interval"), selection: Binding(
                        get: { appState.config.autoBackupIntervalMinutes },
                        set: {
                            appState.config.autoBackupIntervalMinutes = $0
                            appState.saveConfig()
                            appState.scheduler?.startAutoBackup()
                        }
                    )) {
                        Text(String(localized: "15 minutes")).tag(15)
                        Text(String(localized: "30 minutes")).tag(30)
                        Text(String(localized: "1 hour")).tag(60)
                        Text(String(localized: "2 hours")).tag(120)
                        Text(String(localized: "6 hours")).tag(360)
                        Text(String(localized: "Daily")).tag(1440)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    var advancedSettingsTab: some View {
        Form {
            Section(String(localized: "Email Format")) {
                Picker(String(localized: "Format Preset"), selection: Binding(
                    get: { appState.config.formatPreset },
                    set: {
                        appState.config.formatPreset = $0
                        appState.saveConfig()
                    }
                )) {
                    ForEach(FormatPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(appState.config.useCustomFormat)
                
                Toggle(String(localized: "Use Custom Format"), isOn: Binding(
                    get: { appState.config.useCustomFormat },
                    set: {
                        appState.config.useCustomFormat = $0
                        appState.saveConfig()
                    }
                ))
                
                if appState.config.useCustomFormat {
                    Group {
                        Text(String(localized: "Common placeholders: {contact}, {date}, {body}"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField(String(localized: "SMS Subject"), text: Binding(
                            get: { appState.config.smsSubjectFormat },
                            set: { appState.config.smsSubjectFormat = $0; appState.saveConfig() }
                        ))
                        
                        TextField(String(localized: "Call Subject"), text: Binding(
                            get: { appState.config.callSubjectFormat },
                            set: { appState.config.callSubjectFormat = $0; appState.saveConfig() }
                        ))
                        
                        TextField(String(localized: "Calendar Title"), text: Binding(
                            get: { appState.config.calendarTitleFormat },
                            set: { appState.config.calendarTitleFormat = $0; appState.saveConfig() }
                        ))
                    }
                    .fontDesign(.monospaced)
                }
            }
            
            Section(String(localized: "Appearance")) {
                Toggle(isOn: Binding(
                    get: { AppDelegate.isLaunchAtLoginEnabled },
                    set: { newValue in
                        AppDelegate.setLaunchAtLogin(newValue)
                        appState.config.launchAtLogin = newValue
                        appState.saveConfig()
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "Launch at Login"))
                        Text(String(localized: "Start automatically when you log in"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { appState.config.hideDockIcon },
                    set: { newValue in
                        appState.config.hideDockIcon = newValue
                        appState.saveConfig()
                        AppDelegate.shared?.updateDockVisibility(hidden: newValue)
                        
                        if newValue && !appState.config.showMenuBarIcon {
                            appState.addLog(String(localized: "⚠️ Hidden mode enabled."), type: .warning)
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "Hide Dock Icon"))
                        Text(String(localized: "Run in background without Dock icon"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { appState.config.showMenuBarIcon },
                    set: { newValue in
                        appState.config.showMenuBarIcon = newValue
                        UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon")
                        appState.saveConfig()
                        
                        if !newValue && appState.config.hideDockIcon {
                            appState.addLog(String(localized: "⚠️ Hidden mode enabled."), type: .warning)
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "Show Menu Bar Icon"))
                        Text(appState.config.hideDockIcon && !appState.config.showMenuBarIcon
                             ? String(localized: "Hidden mode: Double-click app icon to show window")
                             : String(localized: "Display icon in menu bar for quick access"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.badge.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 8) {
                Text(String(localized: "Mac Message Backup"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(String(format: String(localized: "Version: %@"), "1.0.0"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .frame(width: 300)
            
            VStack(spacing: 12) {
                Text(String(localized: "Inspired by SMS Backup+ for Android"))
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Backup Messages to Gmail"), systemImage: "envelope")
                    Label(String(localized: "Backup Call Log to Gmail"), systemImage: "phone")
                    Label(String(localized: "Backup Call Log to Calendar"), systemImage: "calendar")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("Copyright © 2026 ProcessZero Team. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
    
    // MARK: - Logic
    
    private func testConnection() {
        testingConnection = true
        connectionResult = nil
        
        Task {
            do {
                appState.config.email = email
                if let service = appState.imapService {
                    try service.savePassword(password)
                }
                
                if let service = appState.imapService {
                    let success = try await service.testConnection()
                    await MainActor.run {
                        connectionResult = success ? "✅ " + String(localized: "Connection successful") : "❌ " + String(localized: "Connection failed")
                        testingConnection = false
                    }
                }
            } catch {
                await MainActor.run {
                    connectionResult = "❌ \(error.localizedDescription)"
                    testingConnection = false
                }
            }
        }
    }
    
    private func saveSettings() {
        let emailChanged = appState.config.email != email
        appState.config.email = email
        
        if !password.isEmpty {
            if let service = appState.imapService {
                try? service.savePassword(password)
            }
        }
        
        appState.saveConfig()
        appState.refreshGmailStatus()
        
        if appState.gmailConnected {
            appState.addLog(String(localized: "✅ Settings saved"), type: .success)
        } else {
            appState.addLog(String(localized: "⚠️ Settings saved but Gmail not connected"), type: .warning)
        }
        
        // dismiss() // Optional: keep settings open after save
    }
}

#Preview {
    SettingsView()
}
