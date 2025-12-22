import EventKit
import Foundation

/// Service for syncing call records to local macOS Calendar using EventKit
class LocalCalendarService: ObservableObject {
    
    static let shared = LocalCalendarService()
    
    private let eventStore = EKEventStore()
    
    @Published var isAuthorized = false
    @Published var selectedCalendarId: String?
    @Published var availableCalendars: [EKCalendar] = []
    @Published var error: String?
    
    private init() {
        // Delay check to avoid potential blocking during singleton initialization
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        DispatchQueue.main.async {
            switch status {
            case .authorized, .fullAccess:
                self.isAuthorized = true
                self.loadCalendars()
            case .notDetermined:
                self.isAuthorized = false
            case .denied, .restricted:
                self.isAuthorized = false
                self.error = "Calendar access denied. Please enable in System Settings > Privacy > Calendars."
            case .writeOnly:
                self.isAuthorized = true
                self.loadCalendars()
            @unknown default:
                self.isAuthorized = false
            }
        }
    }
    
    /// Request calendar access permission
    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    self.isAuthorized = granted
                    if granted {
                        self.loadCalendars()
                    }
                }
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                await MainActor.run {
                    self.isAuthorized = granted
                    if granted {
                        self.loadCalendars()
                    }
                }
                return granted
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
            return false
        }
    }
    
    // MARK: - Calendar Management
    
    /// Load available calendars
    func loadCalendars() {
        let calendars = eventStore.calendars(for: .event)
        
        DispatchQueue.main.async {
            self.availableCalendars = calendars.filter { $0.allowsContentModifications }
            
            // Select default calendar if none selected
            if self.selectedCalendarId == nil {
                self.selectedCalendarId = self.eventStore.defaultCalendarForNewEvents?.calendarIdentifier
            }
        }
    }
    
    /// Get selected calendar
    var selectedCalendar: EKCalendar? {
        guard let id = selectedCalendarId else { return nil }
        return availableCalendars.first { $0.calendarIdentifier == id }
    }
    
    // MARK: - Call Record Events
    
    /// Create calendar event for a call record
    func createCallEvent(_ record: CallRecord) throws {
        guard isAuthorized else {
            throw CalendarServiceError.notAuthorized
        }
        
        guard let calendar = selectedCalendar else {
            throw CalendarServiceError.noCalendarSelected
        }
        
        let event = EKEvent(eventStore: eventStore)
        
        // Set event properties
        event.title = record.calendarTitle
        event.notes = record.calendarDescription
        event.startDate = record.date
        event.endDate = record.date.addingTimeInterval(TimeInterval(record.duration))
        event.calendar = calendar
        
        // Add call type as a note/category
        event.url = URL(string: "tel:\(record.address)")
        
        try eventStore.save(event, span: .thisEvent)
    }
    
    /// Create events for multiple call records
    func createCallEvents(_ records: [CallRecord], progressHandler: ((Int, Int) -> Void)? = nil) async throws -> Int {
        guard isAuthorized else {
            throw CalendarServiceError.notAuthorized
        }
        
        var successCount = 0
        
        for (index, record) in records.enumerated() {
            do {
                try createCallEvent(record)
                successCount += 1
            } catch {
                print("Failed to create event for call: \(error)")
            }
            
            progressHandler?(index + 1, records.count)
        }
        
        return successCount
    }
    
    /// Check if event already exists for call record (to avoid duplicates)
    func eventExists(for record: CallRecord) -> Bool {
        guard isAuthorized else { return false }
        
        let startDate = record.date.addingTimeInterval(-60) // 1 minute tolerance
        let endDate = record.date.addingTimeInterval(60)
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: selectedCalendar.map { [$0] })
        let events = eventStore.events(matching: predicate)
        
        return events.contains { event in
            event.title == record.calendarTitle
        }
    }
}

// MARK: - Errors

enum CalendarServiceError: Error, LocalizedError {
    case notAuthorized
    case noCalendarSelected
    case eventCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized"
        case .noCalendarSelected:
            return "No calendar selected"
        case .eventCreationFailed:
            return "Failed to create calendar event"
        }
    }
}
