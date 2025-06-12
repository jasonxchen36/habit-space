import Foundation
import CoreData
import SwiftUI
import Combine

/// Manages all habit-related operations and state for the HabitSpace app
class HabitManager: ObservableObject {
    // MARK: - Published Properties
    
    /// All habits stored in the database
    @Published var habits: [HabitViewModel] = []
    
    /// Habits filtered for today's view
    @Published var todaysHabits: [HabitViewModel] = []
    
    /// Flag indicating if this is the first app launch
    @Published var isFirstLaunch: Bool = false
    
    /// Overall completion rate for the current week (0.0-1.0)
    @Published var weeklyCompletionRate: Double = 0.0
    
    /// Current longest active streak across all habits
    @Published var longestStreak: Int = 0
    
    /// Total habits completed today
    @Published var todayCompletedCount: Int = 0
    
    /// Analytics data for the past 30 days
    @Published var analyticsData: [Date: Double] = [:]
    
    // MARK: - Internal Properties
    
    /// Core Data managed object context
    var viewContext: NSManagedObjectContext?
    
    // MARK: - Private Properties
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Calendar used for date calculations
    private let calendar = Calendar.current
    
    /// Date formatter for consistent date handling
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    // MARK: - Initialization
    
    /// Initialize the HabitManager with Core Data context
    /// - Parameter context: The NSManagedObjectContext to use for database operations
    func initialize(context: NSManagedObjectContext) {
        self.viewContext = context
        loadHabits()
        calculateStatistics()
        
        // Set up timer to refresh habits at midnight
        setupMidnightRefresh()
    }
    
    // MARK: - CRUD Operations
    
    /// Load all habits from Core Data
    func loadHabits() {
        guard let context = viewContext else { return }
        
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Habit.createdAt, ascending: true)]
        
        do {
            let fetchedHabits = try context.fetch(request)
            self.habits = fetchedHabits.map { HabitViewModel(habit: $0) }
            filterTodaysHabits()
            calculateStatistics()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to fetch habits: \(error)")
        }
    }
    
    /// Create a new habit
    /// - Parameters:
    ///   - title: The title of the habit
    ///   - frequency: How often the habit should be performed (daily, weekly, etc.)
    ///   - completion: Optional completion handler
    /// - Returns: The created habit view model
    @discardableResult
    func createHabit(title: String, frequency: HabitFrequency, completion: ((HabitViewModel) -> Void)? = nil) -> HabitViewModel? {
        guard let context = viewContext else { return nil }
        
        let newHabit = Habit(context: context)
        newHabit.id = UUID()
        newHabit.title = title
        newHabit.frequency = frequency.rawValue
        newHabit.streak = 0
        newHabit.createdAt = Date()
        newHabit.isActive = true
        
        do {
            try context.save()
            let viewModel = HabitViewModel(habit: newHabit)
            habits.append(viewModel)
            filterTodaysHabits()
            calculateStatistics()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
            
            completion?(viewModel)
            return viewModel
        } catch {
            print("Failed to create habit: \(error)")
            return nil
        }
    }
    
    /// Update an existing habit
    /// - Parameters:
    ///   - habit: The habit view model to update
    ///   - title: New title (optional)
    ///   - frequency: New frequency (optional)
    ///   - isActive: New active state (optional)
    func updateHabit(habit: HabitViewModel, title: String? = nil, frequency: HabitFrequency? = nil, isActive: Bool? = nil) {
        guard let context = viewContext,
              let habitObject = fetchHabitObject(withId: habit.id) else { return }
        
        if let title = title {
            habitObject.title = title
        }
        
        if let frequency = frequency {
            habitObject.frequency = frequency.rawValue
        }
        
        if let isActive = isActive {
            habitObject.isActive = isActive
        }
        
        do {
            try context.save()
            loadHabits() // Reload to refresh view models
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to update habit: \(error)")
        }
    }
    
    /// Delete a habit
    /// - Parameter habit: The habit view model to delete
    func deleteHabit(habit: HabitViewModel) {
        guard let context = viewContext,
              let habitObject = fetchHabitObject(withId: habit.id) else { return }
        
        context.delete(habitObject)
        
        do {
            try context.save()
            loadHabits()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to delete habit: \(error)")
        }
    }
    
    // MARK: - Habit Completion
    
    /// Mark a habit as completed for today
    /// - Parameter habit: The habit to mark as completed
    func completeHabit(_ habit: HabitViewModel) {
        guard let context = viewContext,
              let habitObject = fetchHabitObject(withId: habit.id) else { return }
        
        // Create log entry
        let logEntry = LogEntry(context: context)
        logEntry.id = UUID()
        logEntry.habitID = habit.id
        logEntry.completedAt = Date()
        logEntry.status = HabitStatus.completed.rawValue
        logEntry.habit = habitObject
        
        // Update streak
        updateStreak(for: habitObject)
        
        do {
            try context.save()
            loadHabits()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to complete habit: \(error)")
        }
    }
    
    /// Skip a habit for today
    /// - Parameter habit: The habit to skip
    func skipHabit(_ habit: HabitViewModel) {
        guard let context = viewContext,
              let habitObject = fetchHabitObject(withId: habit.id) else { return }
        
        // Create log entry with skipped status
        let logEntry = LogEntry(context: context)
        logEntry.id = UUID()
        logEntry.habitID = habit.id
        logEntry.completedAt = Date()
        logEntry.status = HabitStatus.skipped.rawValue
        logEntry.habit = habitObject
        
        do {
            try context.save()
            loadHabits()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to skip habit: \(error)")
        }
    }
    
    /// Reset a habit's completion status for today
    /// - Parameter habit: The habit to reset
    func resetHabitForToday(_ habit: HabitViewModel) {
        guard let context = viewContext else { return }
        
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let predicate = NSPredicate(format: "habitID == %@ AND completedAt >= %@ AND completedAt < %@", 
                                   habit.id as CVarArg, today as NSDate, tomorrow as NSDate)
        request.predicate = predicate
        
        do {
            let entries = try context.fetch(request)
            for entry in entries {
                context.delete(entry)
            }
            try context.save()
            loadHabits()
            
            // Notify other components that habit data has changed
            NotificationCenter.default.post(name: .habitDataChanged, object: nil)
        } catch {
            print("Failed to reset habit: \(error)")
        }
    }
    
    // MARK: - Streak Calculation
    
    /// Update the streak count for a habit
    /// - Parameter habit: The habit to update
    private func updateStreak(for habit: Habit) {
        guard let context = viewContext else { return }
        
        // Get the habit frequency
        let frequency = HabitFrequency(rawValue: habit.frequency ?? HabitFrequency.daily.rawValue) ?? .daily
        
        // Get log entries sorted by date
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "habitID == %@ AND status == %@", 
                                       habit.id as CVarArg, 
                                       HabitStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LogEntry.completedAt, ascending: false)]
        
        do {
            let entries = try context.fetch(request)
            
            // Calculate streak based on frequency
            var streak = 0
            var lastDate: Date?
            
            for entry in entries {
                guard let completedAt = entry.completedAt else { continue }
                
                if let last = lastDate {
                    // Check if this entry continues the streak based on frequency
                    let expectedPreviousDate: Date
                    
                    switch frequency {
                    case .daily:
                        expectedPreviousDate = calendar.date(byAdding: .day, value: -1, to: last)!
                    case .weekly:
                        expectedPreviousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: last)!
                    case .monthly:
                        expectedPreviousDate = calendar.date(byAdding: .month, value: -1, to: last)!
                    }
                    
                    // Check if dates are within the expected range
                    if calendar.isDate(completedAt, inSameDayAs: expectedPreviousDate) ||
                       (frequency == .weekly && calendar.isDate(completedAt, equalTo: expectedPreviousDate, toGranularity: .weekOfYear)) ||
                       (frequency == .monthly && calendar.isDate(completedAt, equalTo: expectedPreviousDate, toGranularity: .month)) {
                        streak += 1
                    } else {
                        // Streak broken
                        break
                    }
                } else {
                    // First entry in streak
                    streak = 1
                }
                
                lastDate = completedAt
            }
            
            // Update habit streak
            habit.streak = Int32(streak)
            try context.save()
            
        } catch {
            print("Failed to calculate streak: \(error)")
        }
    }
    
    /// Calculate streaks for all habits
    func recalculateAllStreaks() {
        guard let context = viewContext else { return }
        
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        
        do {
            let habits = try context.fetch(request)
            for habit in habits {
                updateStreak(for: habit)
            }
        } catch {
            print("Failed to recalculate streaks: \(error)")
        }
    }
    
    // MARK: - Statistics and Analytics
    
    /// Calculate statistics for habits
    func calculateStatistics() {
        calculateWeeklyCompletionRate()
        calculateLongestStreak()
        calculateTodayCompletedCount()
        generateAnalyticsData()
    }
    
    /// Calculate the completion rate for the current week
    private func calculateWeeklyCompletionRate() {
        guard let context = viewContext else { return }
        
        // Get start of week
        let today = Date()
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday as first day of week
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        
        // Count total habits that should be completed this week
        let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        habitRequest.predicate = NSPredicate(format: "isActive == YES")
        
        // Count completed habits this week
        let logRequest: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        logRequest.predicate = NSPredicate(format: "completedAt >= %@ AND status == %@", 
                                          startOfWeek as NSDate, 
                                          HabitStatus.completed.rawValue)
        
        do {
            let activeHabits = try context.fetch(habitRequest)
            let completedLogs = try context.fetch(logRequest)
            
            // Calculate expected completions based on frequency
            var expectedCompletions = 0
            for habit in activeHabits {
                let frequency = HabitFrequency(rawValue: habit.frequency ?? "") ?? .daily
                switch frequency {
                case .daily:
                    // Days since start of week or habit creation (whichever is later)
                    let habitStart = max(startOfWeek, habit.createdAt ?? startOfWeek)
                    let daysSinceStart = calendar.dateComponents([.day], from: habitStart, to: today).day ?? 0
                    expectedCompletions += daysSinceStart + 1
                case .weekly:
                    expectedCompletions += 1
                case .monthly:
                    // Check if this month started within this week
                    let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
                    if startOfMonth >= startOfWeek && startOfMonth <= today {
                        expectedCompletions += 1
                    }
                }
            }
            
            // Calculate completion rate
            if expectedCompletions > 0 {
                weeklyCompletionRate = Double(completedLogs.count) / Double(expectedCompletions)
            } else {
                weeklyCompletionRate = 0
            }
            
        } catch {
            print("Failed to calculate weekly completion rate: \(error)")
            weeklyCompletionRate = 0
        }
    }
    
    /// Find the longest active streak across all habits
    private func calculateLongestStreak() {
        var maxStreak = 0
        
        for habit in habits where habit.isActive {
            maxStreak = max(maxStreak, habit.streak)
        }
        
        longestStreak = maxStreak
    }
    
    /// Count habits completed today
    private func calculateTodayCompletedCount() {
        guard let context = viewContext else { 
            todayCompletedCount = 0
            return
        }
        
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "completedAt >= %@ AND completedAt < %@ AND status == %@", 
                                       today as NSDate, 
                                       tomorrow as NSDate, 
                                       HabitStatus.completed.rawValue)
        
        do {
            let entries = try context.fetch(request)
            todayCompletedCount = entries.count
        } catch {
            print("Failed to calculate today's completed count: \(error)")
            todayCompletedCount = 0
        }
    }
    
    /// Generate analytics data for the past 30 days
    private func generateAnalyticsData() {
        guard let context = viewContext else { return }
        
        let today = calendar.startOfDay(for: Date())
        var analyticsMap: [Date: Double] = [:]
        
        // For each of the past 30 days
        for dayOffset in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
            
            // Count completed habits for this day
            let logRequest: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
            logRequest.predicate = NSPredicate(format: "completedAt >= %@ AND completedAt < %@ AND status == %@", 
                                              date as NSDate, 
                                              nextDay as NSDate, 
                                              HabitStatus.completed.rawValue)
            
            // Count expected habits for this day
            let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
            habitRequest.predicate = NSPredicate(format: "isActive == YES AND createdAt <= %@", nextDay as NSDate)
            
            do {
                let completedLogs = try context.fetch(logRequest)
                let activeHabits = try context.fetch(habitRequest)
                
                // Count daily habits and appropriate weekly/monthly habits
                var expectedCount = 0
                for habit in activeHabits {
                    guard let frequencyString = habit.frequency,
                          let frequency = HabitFrequency(rawValue: frequencyString) else { continue }
                    
                    switch frequency {
                    case .daily:
                        expectedCount += 1
                    case .weekly:
                        // Check if this is the designated day of the week for this habit
                        if calendar.component(.weekday, from: date) == calendar.component(.weekday, from: habit.createdAt ?? date) {
                            expectedCount += 1
                        }
                    case .monthly:
                        // Check if this is the designated day of the month for this habit
                        if calendar.component(.day, from: date) == calendar.component(.day, from: habit.createdAt ?? date) {
                            expectedCount += 1
                        }
                    }
                }
                
                // Calculate completion rate for this day
                let completionRate = expectedCount > 0 ? Double(completedLogs.count) / Double(expectedCount) : 0
                analyticsMap[date] = completionRate
                
            } catch {
                print("Failed to generate analytics for \(dateFormatter.string(from: date)): \(error)")
                analyticsMap[date] = 0
            }
        }
        
        analyticsData = analyticsMap
    }
    
    // MARK: - Onboarding and Default Habits
    
    /// Get default habit templates for onboarding
    /// - Returns: Array of default habit templates
    func getDefaultHabitTemplates() -> [HabitTemplate] {
        return DefaultData.habitTemplates
    }
    
    /// Create default habits from selected templates
    /// - Parameter templates: Array of selected habit templates
    func createDefaultHabits(from templates: [HabitTemplate]) {
        for template in templates {
            createHabit(title: template.title, frequency: template.frequency)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Filter habits for today's view based on frequency
    private func filterTodaysHabits() {
        let today = Date()
        
        todaysHabits = habits.filter { habit in
            guard habit.isActive else { return false }
            
            let frequency = HabitFrequency(rawValue: habit.frequency) ?? .daily
            
            switch frequency {
            case .daily:
                return true
            case .weekly:
                // Check if today is the same day of week as when the habit was created
                guard let createdAt = habit.createdDate else { return false }
                return calendar.component(.weekday, from: today) == calendar.component(.weekday, from: createdAt)
            case .monthly:
                // Check if today is the same day of month as when the habit was created
                guard let createdAt = habit.createdDate else { return false }
                return calendar.component(.day, from: today) == calendar.component(.day, from: createdAt)
            }
        }
    }
    
    /// Fetch a Habit object from Core Data by ID
    /// - Parameter id: The UUID of the habit to fetch
    /// - Returns: The Habit object if found, nil otherwise
    func fetchHabitObject(withId id: UUID) -> Habit? {
        guard let context = viewContext else { return nil }
        
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Failed to fetch habit with ID \(id): \(error)")
            return nil
        }
    }
    
    /// Set up a timer to refresh habits at midnight
    private func setupMidnightRefresh() {
        // Calculate time until next midnight
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let midnight = calendar.startOfDay(for: tomorrow)
        let timeUntilMidnight = midnight.timeIntervalSince(now)
        
        // Schedule one-time timer for midnight
        Timer.scheduledTimer(withTimeInterval: timeUntilMidnight, repeats: false) { [weak self] _ in
            self?.loadHabits()
            self?.calculateStatistics()
            
            // Set up daily timer for subsequent days
            Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
                self?.loadHabits()
                self?.calculateStatistics()
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let habitDataChanged = Notification.Name("habitDataChanged")
}
