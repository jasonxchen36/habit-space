import Foundation
import UserNotifications
import Combine
import CoreLocation
import SwiftUI
import ARKit

/// Manages all notification-related functionality for the HabitSpace app
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    // MARK: - Shared Instance
    
    /// Shared instance for singleton access
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    
    /// Whether notifications are authorized
    @Published var isNotificationAuthorized: Bool = false
    
    /// Whether notifications are enabled for the app
    @Published var areNotificationsEnabled: Bool = false
    
    /// Pending notifications
    @Published var pendingNotifications: [UNNotificationRequest] = []
    
    /// Notification settings
    @Published var notificationSettings: NotificationSettings = NotificationSettings()
    
    /// Recent notifications
    @Published var recentNotifications: [NotificationHistoryItem] = []
    
    // MARK: - Private Properties
    
    /// User notification center
    private let notificationCenter = UNUserNotificationCenter.current()
    
    /// Habit manager reference
    private weak var habitManager: HabitManager?
    
    /// Anchor manager reference
    private weak var anchorManager: AnchorManager?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Background task identifier for proximity checks
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    /// Timer for proximity checks
    private var proximityTimer: Timer?
    
    /// Location manager for geofencing
    private let locationManager = CLLocationManager()
    
    /// Queue for processing notifications
    private let notificationQueue = DispatchQueue(label: "com.habitspace.notificationQueue", qos: .userInitiated)
    
    /// Notification history storage
    private let historyLimit = 50
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Set notification center delegate
        notificationCenter.delegate = self
        
        // Set location manager delegate
        locationManager.delegate = self
        
        // Load notification settings
        loadNotificationSettings()
        
        // Check notification authorization status
        checkAuthorizationStatus()
    }
    
    /// Initialize with dependencies
    /// - Parameters:
    ///   - habitManager: The habit manager instance
    ///   - anchorManager: The anchor manager instance
    func initialize(habitManager: HabitManager, anchorManager: AnchorManager) {
        self.habitManager = habitManager
        self.anchorManager = anchorManager
        
        // Set up notification categories and actions
        registerNotificationCategories()
        
        // Observe changes in habits and anchors
        observeHabitChanges()
        observeAnchorChanges()
        
        // Start monitoring for anchor proximity
        startProximityMonitoring()
    }
    
    // MARK: - Authorization
    
    /// Request notification permissions
    func requestNotificationPermissions() {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert]
        
        notificationCenter.requestAuthorization(options: options) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
                self?.areNotificationsEnabled = granted
                
                if granted {
                    self?.registerForPushNotifications()
                } else if let error = error {
                    print("Notification authorization error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Check current notification authorization status
    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = settings.authorizationStatus == .authorized
                self?.areNotificationsEnabled = settings.alertSetting == .enabled
                
                // Update app badge if needed
                if settings.badgeSetting == .enabled {
                    UIApplication.shared.applicationIconBadgeNumber = self?.calculateBadgeCount() ?? 0
                }
            }
        }
    }
    
    /// Register for push notifications (for remote notifications if needed in the future)
    private func registerForPushNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    // MARK: - Notification Categories and Actions
    
    /// Register custom notification categories and actions
    private func registerNotificationCategories() {
        // Complete action
        let completeAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.complete.rawValue,
            title: "Complete",
            options: [.foreground]
        )
        
        // Skip action
        let skipAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.skip.rawValue,
            title: "Skip",
            options: []
        )
        
        // Snooze action
        let snoozeAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.snooze.rawValue,
            title: "Remind me later",
            options: []
        )
        
        // Habit reminder category
        let habitCategory = UNNotificationCategory(
            identifier: NotificationCategoryIdentifier.habitReminder.rawValue,
            actions: [completeAction, skipAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register categories
        notificationCenter.setNotificationCategories([habitCategory])
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule notifications for all habits
    func scheduleAllNotifications() {
        guard isNotificationAuthorized, areNotificationsEnabled, notificationSettings.isEnabled else {
            return
        }
        
        // Remove existing notifications
        removeAllPendingNotifications()
        
        // Schedule anchor-based notifications
        scheduleAnchorBasedNotifications()
        
        // Schedule time-based notifications
        scheduleTimeBasedNotifications()
        
        // Update pending notifications list
        refreshPendingNotifications()
    }
    
    /// Schedule anchor-based notifications
    private func scheduleAnchorBasedNotifications() {
        guard let habitManager = habitManager,
              let anchorManager = anchorManager else {
            return
        }
        
        // Get all active habits
        let activeHabits = habitManager.habits.filter { $0.isActive }
        
        // Get all active anchors
        let anchors = anchorManager.anchors
        
        // Group anchors by habit
        let habitAnchors = Dictionary(grouping: anchors) { $0.habitId }
        
        // Schedule notifications for each habit with anchors
        for habit in activeHabits {
            if let habitAnchors = habitAnchors[habit.id], !habitAnchors.isEmpty {
                // Skip if habit is already completed today
                if habit.isCompletedToday || habit.isSkippedToday {
                    continue
                }
                
                // Schedule notification for each anchor
                for anchor in habitAnchors {
                    scheduleAnchorNotification(for: habit, anchor: anchor)
                }
            }
        }
    }
    
    /// Schedule a notification for a specific habit and anchor
    /// - Parameters:
    ///   - habit: The habit to schedule for
    ///   - anchor: The anchor to associate with the notification
    private func scheduleAnchorNotification(for habit: HabitViewModel, anchor: AnchorViewModel) {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = habit.title
        content.body = getNotificationMessage(for: habit)
        content.sound = notificationSettings.soundEnabled ? .default : nil
        content.badge = notificationSettings.badgesEnabled ? NSNumber(value: calculateBadgeCount() + 1) : nil
        content.categoryIdentifier = NotificationCategoryIdentifier.habitReminder.rawValue
        
        // Add user info for handling
        content.userInfo = [
            "habitId": habit.id.uuidString,
            "anchorId": anchor.id.uuidString,
            "notificationType": "anchor"
        ]
        
        // For anchor-based notifications, we'll use a location trigger if possible
        // This is a fallback for when AR session is not active
        if let location = getLocationForAnchor(anchor) {
            let region = CLCircularRegion(
                center: location,
                radius: notificationSettings.proximityRadius,
                identifier: anchor.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            
            let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
            
            // Create request
            let request = UNNotificationRequest(
                identifier: "anchor-\(habit.id.uuidString)-\(anchor.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            // Schedule notification
            notificationCenter.add(request) { error in
                if let error = error {
                    print("Error scheduling anchor notification: \(error.localizedDescription)")
                }
            }
        } else {
            // If we can't create a location trigger, we'll rely on the proximity detection
            // in the AnchorManager to trigger notifications directly
        }
    }
    
    /// Schedule time-based notifications for habits
    private func scheduleTimeBasedNotifications() {
        guard let habitManager = habitManager else {
            return
        }
        
        // Get all active habits
        let activeHabits = habitManager.habits.filter { $0.isActive }
        
        for habit in activeHabits {
            // Skip if habit is already completed today
            if habit.isCompletedToday || habit.isSkippedToday {
                continue
            }
            
            // Check if this habit has a preferred time
            if let preferredTime = getPreferredTimeForHabit(habit.id) {
                scheduleTimeBasedNotification(for: habit, at: preferredTime)
            } else if notificationSettings.defaultReminderEnabled {
                // Use default reminder time if enabled
                scheduleTimeBasedNotification(for: habit, at: notificationSettings.defaultReminderTime)
            }
        }
    }
    
    /// Schedule a time-based notification for a habit
    /// - Parameters:
    ///   - habit: The habit to schedule for
    ///   - time: The time to schedule the notification
    private func scheduleTimeBasedNotification(for habit: HabitViewModel, at time: Date) {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = habit.title
        content.body = getNotificationMessage(for: habit)
        content.sound = notificationSettings.soundEnabled ? .default : nil
        content.badge = notificationSettings.badgesEnabled ? NSNumber(value: calculateBadgeCount() + 1) : nil
        content.categoryIdentifier = NotificationCategoryIdentifier.habitReminder.rawValue
        
        // Add user info for handling
        content.userInfo = [
            "habitId": habit.id.uuidString,
            "notificationType": "time"
        ]
        
        // Create date components for trigger
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        // Create trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "time-\(habit.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling time notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Schedule a one-time notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body
    ///   - date: When to deliver the notification
    ///   - userInfo: Additional data to include
    ///   - completion: Callback with success/error
    func scheduleOneTimeNotification(
        title: String,
        body: String,
        date: Date,
        userInfo: [String: Any] = [:],
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSettings.soundEnabled ? .default : nil
        
        // Add user info
        var info = userInfo
        info["notificationType"] = "oneTime"
        content.userInfo = info
        
        // Create date components for trigger
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        
        // Create trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create request with unique identifier
        let identifier = "oneTime-\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling one-time notification: \(error.localizedDescription)")
                completion?(false, error)
            } else {
                completion?(true, nil)
            }
        }
    }
    
    /// Trigger an immediate notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body
    ///   - userInfo: Additional data to include
    func triggerImmediateNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSettings.soundEnabled ? .default : nil
        
        // Add user info
        var info = userInfo
        info["notificationType"] = "immediate"
        content.userInfo = info
        
        // Create trigger (deliver immediately)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request with unique identifier
        let identifier = "immediate-\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error triggering immediate notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Trigger a proximity notification for an anchor
    /// - Parameters:
    ///   - anchor: The anchor in proximity
    func triggerProximityNotification(for anchor: AnchorViewModel) {
        guard let habitManager = habitManager,
              let habit = habitManager.habits.first(where: { $0.id == anchor.habitId }) else {
            return
        }
        
        // Skip if notifications are disabled
        guard isNotificationAuthorized && areNotificationsEnabled && notificationSettings.isEnabled else {
            return
        }
        
        // Skip if habit is already completed or skipped today
        if habit.isCompletedToday || habit.isSkippedToday {
            return
        }
        
        // Skip if we've recently shown a notification for this habit
        if hasRecentlyNotified(habitId: habit.id) {
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = habit.title
        content.body = getNotificationMessage(for: habit)
        content.sound = notificationSettings.soundEnabled ? .default : nil
        content.badge = notificationSettings.badgesEnabled ? NSNumber(value: calculateBadgeCount() + 1) : nil
        content.categoryIdentifier = NotificationCategoryIdentifier.habitReminder.rawValue
        
        // Add user info for handling
        content.userInfo = [
            "habitId": habit.id.uuidString,
            "anchorId": anchor.id.uuidString,
            "notificationType": "proximity"
        ]
        
        // Create request with unique identifier
        let identifier = "proximity-\(habit.id.uuidString)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        // Schedule notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error triggering proximity notification: \(error.localizedDescription)")
            } else {
                // Add to recent notifications
                self.addToNotificationHistory(
                    habitId: habit.id,
                    anchorId: anchor.id,
                    type: .proximity
                )
            }
        }
    }
    
    // MARK: - Notification Management
    
    /// Refresh all notifications
    func refreshNotifications() {
        // Remove existing notifications
        removeAllPendingNotifications()
        
        // Schedule new notifications
        scheduleAllNotifications()
        
        // Update badge count
        updateBadgeCount()
    }
    
    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    /// Remove notifications for a specific habit
    /// - Parameter habitId: The ID of the habit
    func removeNotificationsForHabit(_ habitId: UUID) {
        notificationCenter.getPendingNotificationRequests { requests in
            let identifiersToRemove = requests.compactMap { request -> String? in
                if let requestHabitId = request.content.userInfo["habitId"] as? String,
                   requestHabitId == habitId.uuidString {
                    return request.identifier
                }
                return nil
            }
            
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }
    
    /// Refresh the list of pending notifications
    func refreshPendingNotifications() {
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                self?.pendingNotifications = requests
            }
        }
    }
    
    // MARK: - Badge Management
    
    /// Update the app badge count
    func updateBadgeCount() {
        guard notificationSettings.badgesEnabled else {
            // Clear badge if badges are disabled
            UIApplication.shared.applicationIconBadgeNumber = 0
            return
        }
        
        let badgeCount = calculateBadgeCount()
        UIApplication.shared.applicationIconBadgeNumber = badgeCount
    }
    
    /// Calculate the badge count based on uncompleted habits
    /// - Returns: The badge count
    private func calculateBadgeCount() -> Int {
        guard let habitManager = habitManager else { return 0 }
        
        // Count uncompleted habits for today
        return habitManager.todaysHabits.filter { 
            !$0.isCompletedToday && !$0.isSkippedToday 
        }.count
    }
    
    // MARK: - Notification History
    
    /// Add an entry to the notification history
    /// - Parameters:
    ///   - habitId: The habit ID
    ///   - anchorId: The anchor ID (optional)
    ///   - type: The notification type
    private func addToNotificationHistory(habitId: UUID, anchorId: UUID? = nil, type: NotificationType) {
        let item = NotificationHistoryItem(
            id: UUID(),
            habitId: habitId,
            anchorId: anchorId,
            timestamp: Date(),
            type: type
        )
        
        // Add to recent notifications
        recentNotifications.insert(item, at: 0)
        
        // Limit history size
        if recentNotifications.count > historyLimit {
            recentNotifications = Array(recentNotifications.prefix(historyLimit))
        }
    }
    
    /// Check if a habit has been recently notified
    /// - Parameter habitId: The habit ID to check
    /// - Returns: Whether a notification was recently shown
    private func hasRecentlyNotified(habitId: UUID) -> Bool {
        let recentTimeThreshold: TimeInterval = notificationSettings.minimumNotificationInterval
        
        return recentNotifications.contains { item in
            item.habitId == habitId &&
            Date().timeIntervalSince(item.timestamp) < recentTimeThreshold
        }
    }
    
    // MARK: - Proximity Detection
    
    /// Start monitoring for proximity to anchors
    func startProximityMonitoring() {
        // Request location permissions if needed
        requestLocationPermissions()
        
        // Start monitoring regions for anchors
        setupGeofencingForAnchors()
        
        // Start background task for proximity checks
        startBackgroundTask()
    }
    
    /// Request location permissions
    private func requestLocationPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// Set up geofencing for anchors
    private func setupGeofencingForAnchors() {
        guard let anchorManager = anchorManager else { return }
        
        // Clear existing regions
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        
        // Set up regions for anchors
        for anchor in anchorManager.anchors {
            if let location = getLocationForAnchor(anchor) {
                let region = CLCircularRegion(
                    center: location,
                    radius: notificationSettings.proximityRadius,
                    identifier: anchor.id.uuidString
                )
                region.notifyOnEntry = true
                region.notifyOnExit = false
                
                locationManager.startMonitoring(for: region)
            }
        }
    }
    
    /// Start background task for proximity checks
    private func startBackgroundTask() {
        // End any existing background task
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        
        // Begin a new background task
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "ProximityCheck") {
            // Expiration handler
            UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
            self.backgroundTaskIdentifier = .invalid
        }
        
        // Schedule periodic proximity checks
        // In a real app, this would use BGTaskScheduler for iOS 13+
    }
    
    /// Get location for an anchor
    /// - Parameter anchor: The anchor to get location for
    /// - Returns: The location if available
    private func getLocationForAnchor(_ anchor: AnchorViewModel) -> CLLocationCoordinate2D? {
        // In a real app, we would store geolocation with each anchor
        // For this MVP, we'll return nil and rely on AR proximity detection
        return nil
    }
    
    // MARK: - Settings Management
    
    /// Load notification settings from UserDefaults
    private func loadNotificationSettings() {
        if let data = UserDefaults.standard.data(forKey: "notificationSettings"),
           let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            notificationSettings = settings
        }
    }
    
    /// Save notification settings to UserDefaults
    func saveNotificationSettings() {
        if let data = try? JSONEncoder().encode(notificationSettings) {
            UserDefaults.standard.set(data, forKey: "notificationSettings")
        }
    }
    
    /// Update notification settings
    /// - Parameter settings: The new settings
    func updateSettings(_ settings: NotificationSettings) {
        notificationSettings = settings
        saveNotificationSettings()
        
        // Refresh notifications with new settings
        refreshNotifications()
    }
    
    // MARK: - Helper Methods
    
    /// Get a notification message for a habit
    /// - Parameter habit: The habit to get a message for
    /// - Returns: A notification message
    private func getNotificationMessage(for habit: HabitViewModel) -> String {
        // Get custom message if available
        if let customMessage = getCustomMessageForHabit(habit.id) {
            return customMessage
        }
        
        // Use default messages based on habit type
        let defaultMessages = [
            "Time for your \(habit.title) habit!",
            "Don't forget to \(habit.title.lowercased())!",
            "Ready to \(habit.title.lowercased())? Now's a good time!",
            "Reminder: \(habit.title)"
        ]
        
        return defaultMessages.randomElement() ?? "Time for your habit!"
    }
    
    /// Get a custom message for a habit
    /// - Parameter habitId: The habit ID
    /// - Returns: A custom message if available
    private func getCustomMessageForHabit(_ habitId: UUID) -> String? {
        // In a real app, we would store custom messages in UserDefaults or Core Data
        return nil
    }
    
    /// Get preferred time for a habit
    /// - Parameter habitId: The habit ID
    /// - Returns: The preferred time if set
    private func getPreferredTimeForHabit(_ habitId: UUID) -> Date? {
        // In a real app, we would store preferred times in UserDefaults or Core Data
        return nil
    }
    
    // MARK: - Observation
    
    /// Observe changes in habits
    private func observeHabitChanges() {
        NotificationCenter.default.publisher(for: .habitDataChanged)
            .sink { [weak self] _ in
                self?.refreshNotifications()
            }
            .store(in: &cancellables)
    }
    
    /// Observe changes in anchors
    private func observeAnchorChanges() {
        NotificationCenter.default.publisher(for: .anchorDataChanged)
            .sink { [weak self] _ in
                self?.setupGeofencingForAnchors()
                self?.refreshNotifications()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Called when a notification is about to be presented
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Determine how to present the notification
        var presentationOptions: UNNotificationPresentationOptions = []
        
        if notificationSettings.showBannerWhenActive {
            if #available(iOS 14.0, *) {
                presentationOptions.insert(.banner)
            } else {
                presentationOptions.insert(.alert)
            }
        }
        
        if notificationSettings.soundEnabled {
            presentationOptions.insert(.sound)
        }
        
        if notificationSettings.badgesEnabled {
            presentationOptions.insert(.badge)
        }
        
        // Present the notification
        completionHandler(presentationOptions)
    }
    
    /// Called when a notification response is received
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract user info from notification
        let userInfo = response.notification.request.content.userInfo
        
        // Handle based on action identifier
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // Default action (tapping the notification)
            handleNotificationTap(userInfo)
            
        case NotificationActionIdentifier.complete.rawValue:
            // Complete action
            handleCompleteAction(userInfo)
            
        case NotificationActionIdentifier.skip.rawValue:
            // Skip action
            handleSkipAction(userInfo)
            
        case NotificationActionIdentifier.snooze.rawValue:
            // Snooze action
            handleSnoozeAction(userInfo)
            
        default:
            break
        }
        
        // Update badge count
        updateBadgeCount()
        
        completionHandler()
    }
    
    // MARK: - Notification Action Handlers
    
    /// Handle notification tap
    /// - Parameter userInfo: The notification user info
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        guard let habitIdString = userInfo["habitId"] as? String,
              let habitId = UUID(uuidString: habitIdString) else {
            return
        }
        
        // Post notification to open habit detail
        NotificationCenter.default.post(
            name: .openHabitDetail,
            object: nil,
            userInfo: ["habitId": habitId]
        )
        
        // If there's an anchor ID, focus on it in AR view
        if let anchorIdString = userInfo["anchorId"] as? String,
           let anchorId = UUID(uuidString: anchorIdString) {
            NotificationCenter.default.post(
                name: .focusOnAnchor,
                object: nil,
                userInfo: ["anchorId": anchorId]
            )
        }
    }
    
    /// Handle complete action
    /// - Parameter userInfo: The notification user info
    private func handleCompleteAction(_ userInfo: [AnyHashable: Any]) {
        guard let habitIdString = userInfo["habitId"] as? String,
              let habitId = UUID(uuidString: habitIdString),
              let habitManager = habitManager,
              let habit = habitManager.habits.first(where: { $0.id == habitId }) else {
            return
        }
        
        // Mark habit as completed
        habitManager.completeHabit(habit)
    }
    
    /// Handle skip action
    /// - Parameter userInfo: The notification user info
    private func handleSkipAction(_ userInfo: [AnyHashable: Any]) {
        guard let habitIdString = userInfo["habitId"] as? String,
              let habitId = UUID(uuidString: habitIdString),
              let habitManager = habitManager,
              let habit = habitManager.habits.first(where: { $0.id == habitId }) else {
            return
        }
        
        // Mark habit as skipped
        habitManager.skipHabit(habit)
    }
    
    /// Handle snooze action
    /// - Parameter userInfo: The notification user info
    private func handleSnoozeAction(_ userInfo: [AnyHashable: Any]) {
        guard let habitIdString = userInfo["habitId"] as? String,
              let habitId = UUID(uuidString: habitIdString),
              let habitManager = habitManager,
              let habit = habitManager.habits.first(where: { $0.id == habitId }) else {
            return
        }
        
        // Schedule a reminder in 30 minutes
        let snoozeTime = Date().addingTimeInterval(30 * 60) // 30 minutes
        
        scheduleOneTimeNotification(
            title: habit.title,
            body: "Reminder: Don't forget to \(habit.title.lowercased())",
            date: snoozeTime,
            userInfo: ["habitId": habitId.uuidString, "snoozed": true]
        )
    }
}

// MARK: - CLLocationManagerDelegate
extension NotificationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Handle region entry for geofencing
        if let circularRegion = region as? CLCircularRegion,
           let anchorId = UUID(uuidString: region.identifier),
           let anchorManager = anchorManager,
           let anchor = anchorManager.anchors.first(where: { $0.id == anchorId }) {
            
            // Trigger proximity notification
            triggerProximityNotification(for: anchor)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Use location updates for proximity detection
        // In a real app, we would check distance to anchor locations
    }
}

// MARK: - Background Processing
extension NotificationManager {
    /// Register background processing tasks
    func registerBackgroundTasks() {
        // In a real app, we would use BGTaskScheduler for iOS 13+
        // For this MVP, we'll use background location updates
    }
    
    /// Handle app entering background
    func applicationDidEnterBackground() {
        // Start background task for proximity checks
        startBackgroundTask()
    }
    
    /// Handle app becoming active
    func applicationDidBecomeActive() {
        // End background task if running
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        
        // Update badge count
        updateBadgeCount()
        
        // Refresh notifications
        refreshNotifications()
    }
}
