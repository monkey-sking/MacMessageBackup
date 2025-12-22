import SwiftUI

/// 重新设计的设置视图 - 简洁清晰，完全中文化
/// 重新设计的设置视图 - 简洁清晰，完全中文化
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var oauthService = GoogleOAuthService()
    @ObservedObject private var localCalendarService = LocalCalendarService.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var testingConnection = false
    @State private var connectionResult: String?
    @State private var selectedTab: Int
    let targetTab: Int
    
    init(initialTab: Int = 0) {
        self.targetTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标签栏
            HStack(spacing: 0) {
                TabButton(title: "Gmail", icon: "envelope.fill", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: String(localized: "Backup"), icon: "arrow.clockwise.circle.fill", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabButton(title: String(localized: "About"), icon: "info.circle.fill", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            Divider()
                .padding(.top, 12)
            
            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case 0:
                        gmailSettingsContent
                    case 1:
                        backupSettingsContent
                    case 2:
                        aboutContent
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 580)
        .onAppear {
            email = appState.config.email
            // Do NOT pre-fill password to avoid Keychain prompt
            // Password field will be empty initially for security and to prevent prompts
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Gmail 设置
    
    var gmailSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 连接状态卡片
            connectionStatusCard
            
            // Gmail 账号设置
            SettingsSection(title: String(localized: "Gmail Account")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsTextField(
                        title: String(localized: "Email"),
                        placeholder: "example@gmail.com",
                        text: $email
                    )
                    
                    SettingsSecureField(
                        title: String(localized: "App Password"),
                        placeholder: "xxxx xxxx xxxx xxxx",
                        text: $password
                    )
                    
                    Text(String(localized: "Use a Gmail App Password, not your regular password."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Link(String(localized: "How to create an App Password"),
                         destination: URL(string: "https://support.google.com/accounts/answer/185833")!)
                        .font(.caption)
                }
            }
            
            // 备份标签设置
            SettingsSection(title: String(localized: "Backup Labels")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsTextField(
                        title: String(localized: "SMS Label"),
                        placeholder: "SMS",
                        text: Binding(
                            get: { appState.config.smsLabel },
                            set: { appState.config.smsLabel = $0 }
                        )
                    )
                    
                    SettingsTextField(
                        title: String(localized: "Call Log Label"),
                        placeholder: "Call log",
                        text: Binding(
                            get: { appState.config.callLogLabel },
                            set: { appState.config.callLogLabel = $0 }
                        )
                    )
                }
            }
            
            // 操作按钮
            HStack {
                Button(action: testConnection) {
                    HStack {
                        if testingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(String(localized: "Test Connection"))
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || testingConnection)
                
                Spacer()
                
                Button(String(localized: "Save")) {
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
                        .font(.caption)
                }
            }
        }
    }
    
    var connectionStatusCard: some View {
        HStack {
            Image(systemName: appState.gmailConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(appState.gmailConnected ? .green : .orange)
            
            VStack(alignment: .leading) {
                Text(appState.gmailConnected ? String(localized: "Gmail Connected") : String(localized: "Gmail Not Connected"))
                    .font(.headline)
                
                if appState.gmailConnected, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - 备份设置
    
    var backupSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 备份内容
            SettingsSection(title: String(localized: "Backup Options")) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsToggle(
                        title: String(localized: "Backup Messages to Gmail"),
                        isOn: Binding(
                            get: { appState.config.backupMessages },
                            set: { 
                                appState.config.backupMessages = $0
                                appState.saveConfig()
                            }
                        )
                    )
                    
                    SettingsToggle(
                        title: String(localized: "Backup Call Log to Gmail"),
                        isOn: Binding(
                            get: { appState.config.backupCallLog },
                            set: { 
                                appState.config.backupCallLog = $0 
                                appState.saveConfig()
                            }
                        )
                    )
                }
            }
            
            // 日历同步
            SettingsSection(title: String(localized: "Calendar Backup")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        title: String(localized: "Backup Call Log to Calendar"),
                        isOn: Binding(
                            get: { appState.config.calendarSyncEnabled },
                            set: { 
                                appState.config.calendarSyncEnabled = $0 
                                appState.saveConfig()
                            }
                        )
                    )
                    
                    if appState.config.calendarSyncEnabled {
                        if !localCalendarService.isAuthorized {
                            HStack {
                                Spacer()
                                Button(String(localized: "Connect Calendar")) {
                                    Task {
                                        _ = await localCalendarService.requestAccess()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            // Calendar Picker
                            HStack {
                                Text(String(localized: "Select Calendar"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: Binding(
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
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 200)
                            }
                        }
                    }
                }
            }
            
            // 邮件格式设置
            SettingsSection(title: String(localized: "Email Format")) {
                VStack(alignment: .leading, spacing: 12) {
                    // Preset selector
                    HStack {
                        Text(String(localized: "Format Preset"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
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
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .disabled(appState.config.useCustomFormat)
                    }
                    
                    // Custom format toggle
                    SettingsToggle(
                        title: String(localized: "Use Custom Format"),
                        isOn: Binding(
                            get: { appState.config.useCustomFormat },
                            set: { 
                                appState.config.useCustomFormat = $0 
                                appState.saveConfig()
                            }
                        )
                    )
                    
                    // Custom format fields (shown when custom is enabled)
                    if appState.config.useCustomFormat {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Available placeholders: {contact}, {type}, {date}, {duration}, {emoji}"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text(String(localized: "SMS Subject"))
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                TextField("", text: Binding(
                                    get: { appState.config.smsSubjectFormat },
                                    set: { 
                                        appState.config.smsSubjectFormat = $0 
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            }
                            
                            HStack {
                                Text(String(localized: "Call Subject"))
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                TextField("", text: Binding(
                                    get: { appState.config.callSubjectFormat },
                                    set: { 
                                        appState.config.callSubjectFormat = $0 
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            }
                            
                            HStack {
                                Text(String(localized: "Calendar Title"))
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                TextField("", text: Binding(
                                    get: { appState.config.calendarTitleFormat },
                                    set: { 
                                        appState.config.calendarTitleFormat = $0 
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            }
                            
                            HStack {
                                Text(String(localized: "Call Body"))
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                TextField("", text: Binding(
                                    get: { appState.config.callBodyFormat },
                                    set: { 
                                        appState.config.callBodyFormat = $0 
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Preview"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let sampleContact = "+8613800138000"
                        let sampleType = String(localized: "incoming call")
                        let sampleDuration = 90
                        let sampleDurationFormatted = "00:01:30"
                        
                        let smsSubjectPreview = appState.config.formatSmsSubject(contact: sampleContact, date: Date())
                        let callSubjectPreview = appState.config.formatCallSubject(contact: sampleContact, type: sampleType, duration: sampleDurationFormatted, date: Date())
                        let callBodyPreview = appState.config.formatCallBody(contact: sampleContact, type: sampleType, duration: sampleDuration, durationFormatted: sampleDurationFormatted, date: Date())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(String(localized: "SMS Subject:"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                                Text(smsSubjectPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                            HStack(alignment: .top) {
                                Text(String(localized: "Call Subject:"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                                Text(callSubjectPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                            HStack(alignment: .top) {
                                Text(String(localized: "Call Body:"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                                Text(callBodyPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }
            
            // 自动备份
            SettingsSection(title: String(localized: "Auto Backup")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        title: String(localized: "Enable Auto Backup"),
                        isOn: Binding(
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
                        )
                    )
                    
                    if appState.config.autoBackupEnabled {
                        HStack {
                            Text(String(localized: "Backup Interval"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Picker("", selection: Binding(
                                get: { appState.config.autoBackupIntervalMinutes },
                                set: { 
                                    appState.config.autoBackupIntervalMinutes = $0
                                    appState.saveConfig()
                                    // Restart scheduler with new interval
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
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                    }
                }
            }
            
            // 外观设置
            SettingsSection(title: String(localized: "Appearance")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        title: String(localized: "Hide Dock Icon"),
                        description: String(localized: "Run in background with menu bar icon only"),
                        isOn: Binding(
                            get: { appState.config.hideDockIcon },
                            set: { newValue in
                                appState.config.hideDockIcon = newValue
                                appState.saveConfig()
                                AppDelegate.shared?.updateDockVisibility(hidden: newValue)
                            }
                        )
                    )
                    
                    SettingsToggle(
                        title: String(localized: "Show Menu Bar Icon"),
                        description: String(localized: "Display icon in menu bar for quick access"),
                        isOn: Binding(
                            get: { appState.config.showMenuBarIcon },
                            set: { newValue in
                                // Safety check: don't hide menu bar if Dock is also hidden
                                if !newValue && appState.config.hideDockIcon {
                                    // Show warning and prevent hiding
                                    appState.activeAlert = AppState.AlertItem(
                                        title: String(localized: "Cannot Hide Menu Bar"),
                                        message: String(localized: "Menu bar icon cannot be hidden when Dock icon is also hidden. This would make the app inaccessible."),
                                        type: .error
                                    )
                                    return
                                }
                                appState.config.showMenuBarIcon = newValue
                                // Update @AppStorage via UserDefaults to sync with App's MenuBarExtra binding
                                UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon")
                                appState.saveConfig()
                            }
                        )
                    )
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - 关于
    
    var aboutContent: some View {
        VStack(spacing: 24) {
            // App 图标和名称
            VStack(spacing: 12) {
                Image(systemName: "message.badge.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)
                
                Text("Mac Message Backup")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(String(localized: "A lightweight backup solution for iMessage and Call History"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text(String(localized: "Version") + " 1.0.0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // 说明
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Inspired by SMS Backup+ for Android"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("• " + String(localized: "Backup Messages to Gmail"))
                    .font(.caption)
                
                Text("• " + String(localized: "Backup Call Log to Gmail"))
                    .font(.caption)
                
                Text("• " + String(localized: "Backup Call Log to Calendar"))
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func testConnection() {
        testingConnection = true
        connectionResult = nil
        
        Task {
            do {
                // 保存当前设置
                appState.config.email = email
                if let service = appState.imapService {
                    try service.savePassword(password)
                }
                
                // 测试连接
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
        // Check if email changed
        let emailChanged = appState.config.email != email
        
        appState.config.email = email
        
        if !password.isEmpty {
            if let service = appState.imapService {
                try? service.savePassword(password)
            }
        } else if emailChanged {
            // If email changed and no new password provided, 
            // the new email has no password in keychain (unless previously saved).
            // We do NOT delete the old email's password here just in case,
            // but we don't save an empty one for the new email.
        }
        
        appState.saveConfig()
        
        // Refresh status based on actual keychain state for the (possibly new) email
        appState.refreshGmailStatus()
        
        if appState.gmailConnected {
            appState.addLog(String(localized: "✅ Settings saved"), type: .success)
        } else {
            appState.addLog(String(localized: "⚠️ Settings saved but Gmail not connected"), type: .warning)
        }
        
        dismiss() // Close on save
    }
}

// MARK: - 自定义组件

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? .blue : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle()) // Ensure the entire area is tappable even when transparent
        }
        .buttonStyle(.plain)
        .focusable(false) // Remove focus ring (blue border) causing confusion
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            content
        }
    }
}

struct SettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsToggle: View {
    let title: String
    var description: String? = nil
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
}
