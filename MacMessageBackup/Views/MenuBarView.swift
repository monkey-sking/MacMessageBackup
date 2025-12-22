import SwiftUI

/// Menu bar dropdown view for quick access
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Image("MenuBarIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(String(localized: "Mac Message Backup"))
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            // Quick stats
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(appState.messagesDbConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(String(localized: "Messages") + ": \(appState.totalMessages)")
                }
                
                HStack {
                    Circle()
                        .fill(appState.callHistoryDbConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(String(localized: "Call Records") + ": \(appState.totalCallRecords)")
                }
                
                if let lastDate = appState.config.lastMessageBackupDate {
                    Text(String(localized: "Last backup:") + " \(lastDate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Status/Progress Area
            if appState.isBackingUp {
                VStack(spacing: 4) {
                    // Show actual progress bar
                    if appState.backupProgressValue > 0 {
                        ProgressView(value: appState.backupProgressValue)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    }
                    
                    // Show detailed progress text (e.g. "Message 50/500 backed up")
                    Text(appState.backupProgress.isEmpty ? appState.statusMessage : appState.backupProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }
            
            // Actions
            VStack(spacing: 4) {
                Button(action: {
                    appState.startBackup()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "Backup Now"))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                // Disable button when backing up (user explicitly requested no Cancel button here)
                .disabled(appState.isBackingUp)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Quick toggle for auto backup
            Toggle(isOn: Binding(
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
            )) {
                Label(String(localized: "Auto Backup"), systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            
            Divider()
            
            // Menu items
            Button(action: {
                // Show main window using openWindow (works even if closed)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                HStack {
                    Image(systemName: "macwindow")
                    Text(String(localized: "Show Window"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            Button(action: {
                // Activate main app first
                NSApp.activate(ignoringOtherApps: true)
                // Open explicit Settings window
                openWindow(id: "settings")
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text(String(localized: "Settings..."))
                    Spacer()
                    Text("⌘,")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text(String(localized: "Quit"))
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .padding(.bottom, 8)
        }
        .frame(width: 220)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
