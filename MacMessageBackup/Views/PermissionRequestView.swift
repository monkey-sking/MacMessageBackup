import SwiftUI

/// View shown when Full Disk Access is not granted
struct PermissionRequestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject var permissionHelper = PermissionHelper.shared
    @State private var isChecking = false
    var onSkip: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange.gradient)
            
            // Title
            Text("permission.title".localized)
                .font(.title)
                .fontWeight(.bold)
            
            // Description
            Text("permission.description".localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Steps
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "permission.step1".localized)
                StepRow(number: 2, text: "permission.step2".localized)
                StepRow(number: 3, text: "permission.step3".localized)
                StepRow(number: 4, text: "permission.step4".localized)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Buttons
            HStack(spacing: 16) {
                Button(action: {
                    permissionHelper.openFullDiskAccessSettings()
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("permission.open_settings".localized)
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    checkPermission()
                }) {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("permission.check".localized)
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isChecking)
            }
            
            // Skip button
            if onSkip != nil {
                Button(action: {
                    onSkip?()
                }) {
                    Text(String(localized: "Skip for now"))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            
            // Hint
            if let bundleURL = permissionHelper.getAppBundleURL() {
                VStack(spacing: 4) {
                    Text("permission.app_location".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                    }) {
                        Text(bundleURL.path)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func checkPermission() {
        isChecking = true
        
        // Longer delay to ensure system has updated permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            permissionHelper.refreshPermissionStatus()
            
            // Directly refresh AppState database connections
            appState.refreshDatabaseConnections()
            
            // Also rerun startup checks to update logs
            appState.performStartupChecks()
            
            // Check again after a brief delay to ensure state is updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isChecking = false
                
                // If connected, automatically dismiss the dialog
                if self.appState.messagesDbConnected || self.appState.callHistoryDbConnected {
                    self.dismiss()
                }
            }
        }
    }
}

// Notification name for refreshing database connections
extension Notification.Name {
    static let refreshDatabaseConnections = Notification.Name("refreshDatabaseConnections")
}

/// Step row for permission instructions
struct StepRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            
            Text(text)
                .font(.callout)
        }
    }
}

#Preview {
    PermissionRequestView()
        .frame(width: 500, height: 600)
}

// MARK: - Calendar Permission View

import EventKit

struct CalendarPermissionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject var localCalendarService = LocalCalendarService.shared
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "calendar")
                .font(.system(size: 64))
                .foregroundStyle(localCalendarService.isAuthorized ? Color.green : Color.orange)
            
            // Title
            Text(String(localized: "Connect Calendar"))
                .font(.title)
                .fontWeight(.bold)
            
            // Description
            Text(localCalendarService.isAuthorized 
                 ? String(localized: "Calendar access granted. Please select a calendar to sync call logs to.")
                 : String(localized: "Access to your calendar is required to sync call history."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Content Area
            if !localCalendarService.isAuthorized {
                // Request Access State
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            _ = await localCalendarService.requestAccess()
                            appState.refreshCalendarStatus()
                        }
                    }) {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            Text(String(localized: "Grant Access"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text(String(localized: "You will be prompted to allow access to your Calendar."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                
            } else {
                // Selection State
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Select Calendar"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Picker("", selection: Binding(
                        get: { appState.config.calendarId },
                        set: { appState.config.calendarId = $0 }
                    )) {
                        Text(String(localized: "Select a calendar")).tag("primary")
                        ForEach(localCalendarService.availableCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    
                    if appState.config.calendarId.isEmpty || appState.config.calendarId == "primary" {
                        Text(String(localized: "Please select a specific calendar."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(String(localized: "Call logs will be synced to this calendar."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .frame(maxWidth: 300)
            }
            
            Spacer()
            
            // Done Button
            Button(String(localized: "Done")) {
                appState.refreshCalendarStatus()
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 500, height: 450)
    }
}

#Preview("Calendar Permission") {
    CalendarPermissionView()
        .environmentObject(AppState())
}
