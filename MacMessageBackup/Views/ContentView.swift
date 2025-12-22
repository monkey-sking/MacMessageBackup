import SwiftUI

/// Main application content view
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var permissionHelper = PermissionHelper.shared
    @State private var skipPermissionCheck = false
    @State private var settingsTab = 0
    @State private var showPermissionSheet = false
    // @State private var showSettings = false // Moved to AppState
    @State private var showCalendarPermission = false // New sheet for calendar
    @State private var isLogExpanded = true
    @State private var settingsId = UUID()
    
    var body: some View {
        mainContentView

            .sheet(isPresented: $showPermissionSheet) {
                PermissionRequestView(onSkip: {
                    showPermissionSheet = false
                })
            }
            .sheet(isPresented: $showCalendarPermission) {
                 CalendarPermissionView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showSettings) {
                 NavigationStack {
                    SettingsView(initialTab: settingsTab)
                }
                .environmentObject(appState)
                .id(settingsId) // Force recreation with unique ID
            }
            .onChange(of: appState.showSettings) { isShown in
                if isShown {
                    settingsId = UUID() // Generate new ID when sheet opens
                }
            }
            .alert(item: $appState.activeAlert) { alertItem in
                Alert(
                    title: Text(alertItem.title),
                    message: Text(alertItem.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
    
    var mainContentView: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section(String(localized: "Status")) {
                    StatusRow(
                        icon: "message.fill",
                        title: String(localized: "Messages Database"),
                        status: appState.messagesDbConnected ? String(localized: "Connected") : String(localized: "Not Connected"),
                        isConnected: appState.messagesDbConnected,
                        action: {
                            appState.refreshDatabaseConnections()
                            if !appState.messagesDbConnected {
                                showPermissionSheet = true
                            } else {
                                appState.statusMessage = String(localized: "✅ Messages Database Connected")
                                appState.addLog(String(localized: "✅ Messages Database Connected"), type: .success)
                            }
                        }
                    )
                    
                    StatusRow(
                        icon: "phone.fill",
                        title: String(localized: "Call History"),
                        status: appState.callHistoryDbConnected ? String(localized: "Connected") : String(localized: "Not Connected"),
                        isConnected: appState.callHistoryDbConnected,
                        action: {
                            appState.refreshDatabaseConnections()
                            if !appState.callHistoryDbConnected {
                                showPermissionSheet = true
                            } else {
                                appState.statusMessage = String(localized: "✅ Call History Connected")
                                appState.addLog(String(localized: "✅ Call History Connected"), type: .success)
                            }
                        }
                    )
                    
                    StatusRow(
                        icon: "envelope.fill",
                        title: String(localized: "Gmail"),
                        status: appState.gmailConnected ? String(localized: "Connected") : String(localized: "Not Connected"),
                        isConnected: appState.gmailConnected,
                        action: {
                            Task {
                                appState.statusMessage = String(localized: "Connecting...")
                                await appState.verifyGmailConnection()
                                
                                if !appState.gmailConnected {
                                    settingsId = UUID() // Force fresh settings view
                                    settingsTab = 0
                                    appState.showSettings = true
                                }
                            }
                        }
                    )
                    
                    StatusRow(
                        icon: "calendar",
                        title: String(localized: "Calendar"),
                        status: LocalCalendarService.shared.isAuthorized ? String(localized: "Connected") : String(localized: "Not Connected"),
                        isConnected: LocalCalendarService.shared.isAuthorized,
                        action: {
                            // Always refresh first
                            appState.refreshCalendarStatus()
                            
                            if appState.calendarConnected {
                                appState.statusMessage = String(localized: "✅ Calendar Connected")
                                appState.addLog(String(localized: "✅ Calendar Connected"), type: .success)
                            } else {
                                // Show dedicated permission/selection sheet
                                showCalendarPermission = true
                            }
                        }
                    )
                }
                
                Section(String(localized: "Backup Statistics")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "Messages"), systemImage: "message")
                            .font(.headline)
                        HStack {
                            Text(String(localized: "Total:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.totalMessages)")
                        }
                        .font(.caption)
                        HStack {
                            Text(String(localized: "Backed up:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.backedUpMessages)")
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                        HStack {
                            Text(String(localized: "Remaining:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.remainingMessages)")
                                .foregroundStyle(appState.remainingMessages > 0 ? .orange : .green)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "Call Records"), systemImage: "phone")
                            .font(.headline)
                        HStack {
                            Text(String(localized: "Total:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.totalCallRecords)")
                        }
                        .font(.caption)
                        HStack {
                            Text(String(localized: "Backed up:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.backedUpCallRecords)")
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                        HStack {
                            Text(String(localized: "Remaining:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.remainingCallRecords)")
                                .foregroundStyle(appState.remainingCallRecords > 0 ? .orange : .green)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    
                    // Reset backup progress button
                    Button(action: {
                        appState.config.lastMessageRowId = 0
                        appState.config.lastCallRecordRowId = 0
                        appState.config.lastCalendarSyncRowId = 0
                        appState.saveConfig()
                        appState.refreshStats()
                        appState.addLog(String(localized: "Backup progress reset"), type: .info)
                    }) {
                        Label(String(localized: "Reset Progress"), systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            
        } detail: {
            NavigationStack {
                // Main content
                VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "message.badge.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("Mac Message Backup")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Backup iMessage & Call History to Gmail")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                // Quick stats cards
                HStack(spacing: 16) {
                    StatCard(
                        icon: "message.fill",
                        title: String(localized: "Messages"),
                        value: "\(appState.totalMessages)",
                        color: .blue
                    )
                    
                    StatCard(
                        icon: "phone.fill",
                        title: String(localized: "Call Records"),
                        value: "\(appState.totalCallRecords)",
                        color: .green
                    )
                }
                .padding(.horizontal, 40)
                
                // Action buttons
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: {
                            if appState.isBackingUp {
                                // Cancel backup
                                appState.cancelBackup()
                            } else {
                                // Sequential checks based on enabled settings
                                appState.refreshDatabaseConnections()
                                
                                if appState.config.backupMessages && !appState.messagesDbConnected {
                                    showPermissionSheet = true
                                } else if appState.config.backupCallLog && !appState.callHistoryDbConnected {
                                    showPermissionSheet = true
                                } else if (appState.config.backupMessages || appState.config.backupCallLog) && !appState.gmailConnected {
                                    appState.showSettings = true
                                    appState.statusMessage = String(localized: "Please configure Gmail first")
                                } else if appState.config.calendarSyncEnabled && !LocalCalendarService.shared.isAuthorized {
                                    appState.refreshCalendarStatus()
                                    if !LocalCalendarService.shared.isAuthorized {
                                        showCalendarPermission = true
                                        appState.statusMessage = String(localized: "Please grant Calendar access")
                                    } else {
                                         appState.startBackup()
                                    }
                                } else {
                                    appState.startBackup()
                                }
                            }
                        }) {
                            HStack {
                                if appState.isBackingUp {
                                    Image(systemName: "xmark.circle.fill")
                                } else {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                }
                                Text(appState.isBackingUp ? String(localized: "Cancel") : String(localized: "Backup Now"))
                            }
                            .frame(width: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.isBackingUp ? .gray : .accentColor)
                        .controlSize(.large)
                        
                    }
                    
                    if appState.isBackingUp {
                        VStack(spacing: 4) {
                            ProgressView(value: appState.backupProgressValue, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 200)
                            
                            Text(appState.backupProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem { Spacer() }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            appState.showSettings = true
                        }) {
                            Label(String(localized: "Settings"), systemImage: "gearshape.fill")
                        }
                    }
                }
                

                
                // Collapsible log view
                DisclosureGroup(
                    isExpanded: $isLogExpanded,
                    content: {
                        VStack(alignment: .leading, spacing: 4) {
                            if appState.logEntries.isEmpty {
                                Text(String(localized: "No log entries."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(Color.clear)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        ForEach(appState.logEntries.reversed()) { entry in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: entry.type.icon)
                                                    .foregroundStyle(entry.type.color)
                                                    .font(.caption)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(entry.message)
                                                        .font(.caption)
                                                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    .padding(8)
                                }
                                .frame(maxHeight: 150)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                                
                                Button("Clear Log") {
                                    appState.clearLogs()
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    },
                    label: {
                        Text(String(localized: "Operation Log"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    isLogExpanded.toggle()
                                }
                            }
                    }
                )
                .padding(.horizontal, 40)
                
                Spacer()

                
                Spacer()
            }
            .frame(minWidth: 500, minHeight: 500)
            }
        }
    }
}

/// Status row in sidebar
// MARK: - Subviews

/// Status row in sidebar
struct StatusRow: View {
    let icon: String
    let title: String
    let status: String
    let isConnected: Bool
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { action?() }) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(isConnected ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle()) // Make full row tappable
        }
        .buttonStyle(.plain)
    }
}

/// Statistics card
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
