import Foundation
import CoreData
import Combine
import SwiftUI
import CoreML

/// Manages AI-powered suggestions and analytics for the HabitSpace app
class AIManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Current suggestions for the user
    @Published var suggestions: [HabitSuggestion] = []
    
    /// Analytics insights
    @Published var insights: [HabitInsight] = []
    
    /// Whether the AI system is enabled
    @Published var isEnabled: Bool = true
    
    /// Whether the AI system is currently analyzing data
    @Published var isAnalyzing: Bool = false
    
    /// Suggestion history for learning
    @Published var suggestionHistory: [SuggestionHistoryItem] = []
    
    // MARK: - Private Properties
    
    /// Core Data managed object context
    private var viewContext: NSManagedObjectContext?
    
    /// Habit manager reference
    private weak var habitManager: HabitManager?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Analysis queue
    private let analysisQueue = DispatchQueue(label: "com.habitspace.aianalysis", qos: .utility)
    
    /// Date formatter for consistent date handling
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Calendar used for date calculations
    private let calendar = Calendar.current
    
    /// ML model for advanced suggestions (future use)
    private var mlModel: MLModel?
    
    /// User preference weights
    private var userPreferences: UserPreferenceWeights = UserPreferenceWeights()
    
    /// Suggestion templates
    private let suggestionTemplates: [SuggestionTemplate] = [
        SuggestionTemplate(
            type: .timeOptimization,
            titleTemplate: "Try %@ at a different time",
            messageTemplate: "You seem to complete '%@' more consistently in the %@. Consider moving this habit to %@.",
            priority: 0.8
        ),
        SuggestionTemplate(
            type: .frequencyAdjustment,
            titleTemplate: "Adjust %@ frequency",
            messageTemplate: "You're struggling with '%@' at its current frequency. Consider changing from %@ to %@.",
            priority: 0.7
        ),
        SuggestionTemplate(
            type: .habitCombination,
            titleTemplate: "Combine habits",
            messageTemplate: "Try combining '%@' with '%@' since you often do them around the same time.",
            priority: 0.6
        ),
        SuggestionTemplate(
            type: .locationChange,
            titleTemplate: "Move your %@ anchor",
            messageTemplate: "Your '%@' habit might work better if you move its anchor to a more visible location.",
            priority: 0.5
        ),
        SuggestionTemplate(
            type: .streakMotivation,
            titleTemplate: "Keep your streak going!",
            messageTemplate: "You're on a %d-day streak with '%@'! Complete it today to keep building momentum.",
            priority: 0.9
        )
    ]
    
    // MARK: - Initialization
    
    /// Initialize the AIManager with dependencies
    /// - Parameter habitManager: The habit manager instance
    func initialize(habitManager: HabitManager) {
        self.habitManager = habitManager
        self.viewContext = habitManager.viewContext
        
        // Load saved suggestions
        loadSuggestions()
        
        // Load user preferences
        loadUserPreferences()
        
        // Set up observation of habit changes
        observeHabitChanges()
        
        // Schedule regular analysis
        scheduleRegularAnalysis()
        
        // Try to load ML model if available
        prepareMLModel()
    }
    
    // MARK: - Suggestion Generation
    
    /// Generate suggestions based on habit data
    /// - Parameter habitManager: The habit manager to use for data
    func generateSuggestions(for habitManager: HabitManager? = nil) {
        // Use provided habit manager or stored reference
        let manager = habitManager ?? self.habitManager
        
        guard let manager = manager, isEnabled else { return }
        
        // Mark as analyzing
        isAnalyzing = true
        
        // Perform analysis on background queue
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Analyze habit patterns
            let habitPatterns = self.analyzeHabitPatterns(manager.habits)
            
            // Generate suggestions based on patterns
            let newSuggestions = self.generateSuggestionsFromPatterns(habitPatterns)
            
            // Filter out suggestions that are similar to existing ones
            let filteredSuggestions = self.filterDuplicateSuggestions(newSuggestions)
            
            // Sort by priority
            let sortedSuggestions = filteredSuggestions.sorted { $0.priority > $1.priority }
            
            // Limit to top suggestions
            let topSuggestions = Array(sortedSuggestions.prefix(3))
            
            // Update on main thread
            DispatchQueue.main.async {
                // Add new suggestions to the list
                self.suggestions.append(contentsOf: topSuggestions)
                
                // Save suggestions
                self.saveSuggestions()
                
                // Mark as no longer analyzing
                self.isAnalyzing = false
            }
        }
    }
    
    /// Analyze habit patterns to identify issues and opportunities
    /// - Parameter habits: The habits to analyze
    /// - Returns: Array of habit patterns
    private func analyzeHabitPatterns(_ habits: [HabitViewModel]) -> [HabitPattern] {
        var patterns: [HabitPattern] = []
        
        for habit in habits {
            // Skip inactive habits
            guard habit.isActive else { continue }
            
            // Get log entries for this habit
            let logEntries = fetchLogEntries(for: habit.id)
            
            // Skip if not enough data
            if logEntries.count < 3 {
                continue
            }
            
            // Analyze completion rate
            let completionRate = calculateCompletionRate(logEntries)
            
            // Analyze completion times
            let completionTimes = analyzeCompletionTimes(logEntries)
            
            // Analyze streak patterns
            let streakPattern = analyzeStreakPattern(habit)
            
            // Analyze frequency appropriateness
            let frequencyPattern = analyzeFrequencyPattern(habit, logEntries)
            
            // Create pattern object
            let pattern = HabitPattern(
                habitId: habit.id,
                habitTitle: habit.title,
                completionRate: completionRate,
                optimalTimeOfDay: completionTimes.optimalTime,
                currentFrequency: HabitFrequency(rawValue: habit.frequency) ?? .daily,
                suggestedFrequency: frequencyPattern.suggestedFrequency,
                streak: habit.streak,
                isStreakAtRisk: streakPattern.isAtRisk,
                missedDaysPattern: frequencyPattern.missedDaysPattern,
                relatedHabits: findRelatedHabits(habit, habits)
            )
            
            patterns.append(pattern)
        }
        
        return patterns
    }
    
    /// Generate suggestions based on identified patterns
    /// - Parameter patterns: The habit patterns to use
    /// - Returns: Array of generated suggestions
    private func generateSuggestionsFromPatterns(_ patterns: [HabitPattern]) -> [HabitSuggestion] {
        var suggestions: [HabitSuggestion] = []
        
        for pattern in patterns {
            // Generate time optimization suggestions
            if let timeOptimization = generateTimeOptimizationSuggestion(pattern) {
                suggestions.append(timeOptimization)
            }
            
            // Generate frequency adjustment suggestions
            if let frequencyAdjustment = generateFrequencyAdjustmentSuggestion(pattern) {
                suggestions.append(frequencyAdjustment)
            }
            
            // Generate streak motivation suggestions
            if let streakMotivation = generateStreakMotivationSuggestion(pattern) {
                suggestions.append(streakMotivation)
            }
            
            // Generate habit combination suggestions
            if let habitCombination = generateHabitCombinationSuggestion(pattern) {
                suggestions.append(habitCombination)
            }
            
            // Generate location change suggestions
            if let locationChange = generateLocationChangeSuggestion(pattern) {
                suggestions.append(locationChange)
            }
        }
        
        return suggestions
    }
    
    /// Generate a time optimization suggestion
    /// - Parameter pattern: The habit pattern to use
    /// - Returns: A suggestion if appropriate
    private func generateTimeOptimizationSuggestion(_ pattern: HabitPattern) -> HabitSuggestion? {
        // Only suggest time changes if completion rate is below threshold
        guard pattern.completionRate < 0.7, let optimalTime = pattern.optimalTimeOfDay else {
            return nil
        }
        
        // Get template
        guard let template = suggestionTemplates.first(where: { $0.type == .timeOptimization }) else {
            return nil
        }
        
        // Format time of day
        let timeOfDayString = formatTimeOfDay(optimalTime)
        let suggestedTimeString = formatTimeString(optimalTime)
        
        // Create message
        let message = String(format: template.messageTemplate, 
                            pattern.habitTitle, 
                            timeOfDayString, 
                            suggestedTimeString)
        
        // Create title
        let title = String(format: template.titleTemplate, pattern.habitTitle)
        
        // Create suggestion
        return HabitSuggestion(
            id: UUID(),
            habitId: pattern.habitId,
            title: title,
            message: message,
            type: .timeOptimization,
            suggestedTime: optimalTime,
            priority: template.priority * (1.0 - pattern.completionRate),
            isAccepted: false,
            createdAt: Date()
        )
    }
    
    /// Generate a frequency adjustment suggestion
    /// - Parameter pattern: The habit pattern to use
    /// - Returns: A suggestion if appropriate
    private func generateFrequencyAdjustmentSuggestion(_ pattern: HabitPattern) -> HabitSuggestion? {
        // Only suggest frequency changes if completion rate is below threshold
        // and we have a suggested frequency different from current
        guard pattern.completionRate < 0.6,
              let suggestedFrequency = pattern.suggestedFrequency,
              suggestedFrequency != pattern.currentFrequency else {
            return nil
        }
        
        // Get template
        guard let template = suggestionTemplates.first(where: { $0.type == .frequencyAdjustment }) else {
            return nil
        }
        
        // Create message
        let message = String(format: template.messageTemplate,
                            pattern.habitTitle,
                            pattern.currentFrequency.displayName,
                            suggestedFrequency.displayName)
        
        // Create title
        let title = String(format: template.titleTemplate, pattern.habitTitle)
        
        // Create suggestion
        return HabitSuggestion(
            id: UUID(),
            habitId: pattern.habitId,
            title: title,
            message: message,
            type: .frequencyAdjustment,
            suggestedFrequency: suggestedFrequency,
            priority: template.priority * (1.0 - pattern.completionRate),
            isAccepted: false,
            createdAt: Date()
        )
    }
    
    /// Generate a streak motivation suggestion
    /// - Parameter pattern: The habit pattern to use
    /// - Returns: A suggestion if appropriate
    private func generateStreakMotivationSuggestion(_ pattern: HabitPattern) -> HabitSuggestion? {
        // Only generate streak motivation for habits with decent streaks that are at risk
        guard pattern.streak >= 3, pattern.isStreakAtRisk else {
            return nil
        }
        
        // Get template
        guard let template = suggestionTemplates.first(where: { $0.type == .streakMotivation }) else {
            return nil
        }
        
        // Create message
        let message = String(format: template.messageTemplate, pattern.streak, pattern.habitTitle)
        
        // Create suggestion
        return HabitSuggestion(
            id: UUID(),
            habitId: pattern.habitId,
            title: template.titleTemplate,
            message: message,
            type: .streakMotivation,
            priority: template.priority,
            isAccepted: false,
            createdAt: Date()
        )
    }
    
    /// Generate a habit combination suggestion
    /// - Parameter pattern: The habit pattern to use
    /// - Returns: A suggestion if appropriate
    private func generateHabitCombinationSuggestion(_ pattern: HabitPattern) -> HabitSuggestion? {
        // Only suggest combinations if we have related habits
        guard let relatedHabit = pattern.relatedHabits.first else {
            return nil
        }
        
        // Get template
        guard let template = suggestionTemplates.first(where: { $0.type == .habitCombination }) else {
            return nil
        }
        
        // Create message
        let message = String(format: template.messageTemplate, pattern.habitTitle, relatedHabit.title)
        
        // Create suggestion
        return HabitSuggestion(
            id: UUID(),
            habitId: pattern.habitId,
            title: template.titleTemplate,
            message: message,
            type: .habitCombination,
            relatedHabitId: relatedHabit.id,
            priority: template.priority * 0.8,
            isAccepted: false,
            createdAt: Date()
        )
    }
    
    /// Generate a location change suggestion
    /// - Parameter pattern: The habit pattern to use
    /// - Returns: A suggestion if appropriate
    private func generateLocationChangeSuggestion(_ pattern: HabitPattern) -> HabitSuggestion? {
        // Only suggest location changes if completion rate is low
        // and we have anchors for this habit
        guard pattern.completionRate < 0.5, hasAnchors(for: pattern.habitId) else {
            return nil
        }
        
        // Get template
        guard let template = suggestionTemplates.first(where: { $0.type == .locationChange }) else {
            return nil
        }
        
        // Create title
        let title = String(format: template.titleTemplate, pattern.habitTitle)
        
        // Create message
        let message = String(format: template.messageTemplate, pattern.habitTitle)
        
        // Create suggestion
        return HabitSuggestion(
            id: UUID(),
            habitId: pattern.habitId,
            title: title,
            message: message,
            type: .locationChange,
            priority: template.priority * (1.0 - pattern.completionRate),
            isAccepted: false,
            createdAt: Date()
        )
    }
    
    // MARK: - Pattern Analysis Helpers
    
    /// Calculate completion rate from log entries
    /// - Parameter logEntries: The log entries to analyze
    /// - Returns: Completion rate as a decimal (0.0-1.0)
    private func calculateCompletionRate(_ logEntries: [LogEntryData]) -> Double {
        // Get entries from the past 14 days
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentEntries = logEntries.filter { $0.completedAt >= twoWeeksAgo }
        
        // Count completed vs. total
        let completedCount = recentEntries.filter { $0.status == HabitStatus.completed.rawValue }.count
        
        // If no entries, return 0
        if recentEntries.isEmpty {
            return 0.0
        }
        
        return Double(completedCount) / Double(recentEntries.count)
    }
    
    /// Analyze completion times to find optimal time of day
    /// - Parameter logEntries: The log entries to analyze
    /// - Returns: Analysis results with optimal time
    private func analyzeCompletionTimes(_ logEntries: [LogEntryData]) -> (optimalTime: Date?, timeDistribution: [Int: Int]) {
        // Filter for completed entries only
        let completedEntries = logEntries.filter { $0.status == HabitStatus.completed.rawValue }
        
        // Group by hour of day
        var hourDistribution: [Int: Int] = [:]
        
        for entry in completedEntries {
            let hour = Calendar.current.component(.hour, from: entry.completedAt)
            hourDistribution[hour, default: 0] += 1
        }
        
        // Find most common hour
        var mostCommonHour = 9 // Default to 9 AM
        var maxCount = 0
        
        for (hour, count) in hourDistribution {
            if count > maxCount {
                maxCount = count
                mostCommonHour = hour
            }
        }
        
        // Create date for optimal time
        var optimalTime: Date?
        if maxCount > 0 {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = mostCommonHour
            components.minute = 0
            optimalTime = Calendar.current.date(from: components)
        }
        
        return (optimalTime, hourDistribution)
    }
    
    /// Analyze streak pattern to determine if at risk
    /// - Parameter habit: The habit to analyze
    /// - Returns: Analysis results
    private func analyzeStreakPattern(_ habit: HabitViewModel) -> (isAtRisk: Bool, streakHistory: [Int]) {
        // A streak is at risk if:
        // 1. It's a significant streak (3+ days)
        // 2. The habit hasn't been completed today
        // 3. It's late in the day
        
        let hasSignificantStreak = habit.streak >= 3
        let notCompletedToday = !habit.isCompletedToday && !habit.isSkippedToday
        
        // Check if it's late in the day (after 5 PM)
        let hour = Calendar.current.component(.hour, from: Date())
        let isLateInDay = hour >= 17
        
        let isAtRisk = hasSignificantStreak && notCompletedToday && isLateInDay
        
        // In a real app, we'd track streak history over time
        let streakHistory: [Int] = []
        
        return (isAtRisk, streakHistory)
    }
    
    /// Analyze frequency pattern to determine if current frequency is appropriate
    /// - Parameters:
    ///   - habit: The habit to analyze
    ///   - logEntries: The log entries to analyze
    /// - Returns: Analysis results
    private func analyzeFrequencyPattern(_ habit: HabitViewModel, _ logEntries: [LogEntryData]) -> (suggestedFrequency: HabitFrequency?, missedDaysPattern: [Int]) {
        let currentFrequency = HabitFrequency(rawValue: habit.frequency) ?? .daily
        let completionRate = calculateCompletionRate(logEntries)
        
        var suggestedFrequency: HabitFrequency?
        var missedDaysPattern: [Int] = []
        
        // If completion rate is low, suggest less frequent habit
        if completionRate < 0.4 {
            switch currentFrequency {
            case .daily:
                suggestedFrequency = .weekly
            case .weekly:
                suggestedFrequency = .monthly
            case .monthly:
                // Already at lowest frequency
                suggestedFrequency = nil
            }
        }
        // If completion rate is very high, suggest more frequent habit
        else if completionRate > 0.9 {
            switch currentFrequency {
            case .monthly:
                suggestedFrequency = .weekly
            case .weekly:
                suggestedFrequency = .daily
            case .daily:
                // Already at highest frequency
                suggestedFrequency = nil
            }
        }
        
        // Analyze which days of week are most commonly missed
        // (This would be more complex in a real implementation)
        
        return (suggestedFrequency, missedDaysPattern)
    }
    
    /// Find habits that might be related to the given habit
    /// - Parameters:
    ///   - habit: The habit to find related habits for
    ///   - allHabits: All habits to search through
    /// - Returns: Array of related habits
    private func findRelatedHabits(_ habit: HabitViewModel, _ allHabits: [HabitViewModel]) -> [HabitViewModel] {
        // In a real implementation, this would analyze completion times
        // and patterns to find habits that are often completed together
        
        // For the MVP, just return a random active habit that isn't this one
        return allHabits.filter { 
            $0.id != habit.id && 
            $0.isActive && 
            !$0.isCompletedToday
        }.prefix(1).map { $0 }
    }
    
    /// Check if a habit has anchors
    /// - Parameter habitId: The habit ID to check
    /// - Returns: Whether the habit has anchors
    private func hasAnchors(for habitId: UUID) -> Bool {
        guard let context = viewContext else { return false }
        
        let request: NSFetchRequest<Anchor> = Anchor.fetchRequest()
        request.predicate = NSPredicate(format: "habitID == %@ AND isActive == YES", habitId as CVarArg)
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Failed to check anchors: \(error)")
            return false
        }
    }
    
    /// Fetch log entries for a habit
    /// - Parameter habitId: The habit ID to fetch entries for
    /// - Returns: Array of log entries
    private func fetchLogEntries(for habitId: UUID) -> [LogEntryData] {
        guard let context = viewContext else { return [] }
        
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "habitID == %@", habitId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LogEntry.completedAt, ascending: false)]
        
        do {
            let entries = try context.fetch(request)
            return entries.compactMap { entry in
                guard let id = entry.id,
                      let habitID = entry.habitID,
                      let completedAt = entry.completedAt,
                      let status = entry.status else {
                    return nil
                }
                
                return LogEntryData(
                    id: id,
                    habitId: habitID,
                    completedAt: completedAt,
                    status: status
                )
            }
        } catch {
            print("Failed to fetch log entries: \(error)")
            return []
        }
    }
    
    /// Filter out duplicate or similar suggestions
    /// - Parameter suggestions: The suggestions to filter
    /// - Returns: Filtered suggestions
    private func filterDuplicateSuggestions(_ suggestions: [HabitSuggestion]) -> [HabitSuggestion] {
        var filteredSuggestions: [HabitSuggestion] = []
        var seenTypes: [UUID: Set<SuggestionType>] = [:]
        
        for suggestion in suggestions {
            // Skip if we already have a suggestion of this type for this habit
            if seenTypes[suggestion.habitId]?.contains(suggestion.type) ?? false {
                continue
            }
            
            // Skip if we already have a similar suggestion in the existing suggestions
            if self.suggestions.contains(where: { 
                $0.habitId == suggestion.habitId && 
                $0.type == suggestion.type &&
                !$0.isAccepted &&
                Calendar.current.isDate($0.createdAt, inSameDayAs: Date())
            }) {
                continue
            }
            
            // Add to filtered list
            filteredSuggestions.append(suggestion)
            
            // Mark this type as seen for this habit
            if seenTypes[suggestion.habitId] == nil {
                seenTypes[suggestion.habitId] = []
            }
            seenTypes[suggestion.habitId]?.insert(suggestion.type)
        }
        
        return filteredSuggestions
    }
    
    // MARK: - Suggestion Management
    
    /// Apply a suggestion
    /// - Parameter suggestion: The suggestion to apply
    func applySuggestion(_ suggestion: HabitSuggestion) {
        guard let habitManager = habitManager else { return }
        
        // Mark as accepted
        markSuggestionAsAccepted(suggestion)
        
        // Apply changes based on suggestion type
        switch suggestion.type {
        case .timeOptimization:
            // In a real app, we would update the preferred time for the habit
            print("Applied time optimization suggestion")
            
        case .frequencyAdjustment:
            if let suggestedFrequency = suggestion.suggestedFrequency,
               let habit = habitManager.habits.first(where: { $0.id == suggestion.habitId }) {
                // Update habit frequency
                habitManager.updateHabit(
                    habit: habit,
                    frequency: suggestedFrequency
                )
            }
            
        case .streakMotivation:
            // This is just motivational, no action needed
            print("Applied streak motivation suggestion")
            
        case .habitCombination:
            // In a real app, we might create a combined habit or link them
            print("Applied habit combination suggestion")
            
        case .locationChange:
            // In a real app, we would prompt the user to move the anchor
            print("Applied location change suggestion")
            
        case .custom:
            // Custom suggestions would have their own handling
            print("Applied custom suggestion")
        }
        
        // Add to suggestion history
        addToSuggestionHistory(suggestion, wasAccepted: true)
        
        // Remove from active suggestions
        removeSuggestion(suggestion)
    }
    
    /// Dismiss a suggestion without applying it
    /// - Parameter suggestion: The suggestion to dismiss
    func dismissSuggestion(_ suggestion: HabitSuggestion) {
        // Add to suggestion history
        addToSuggestionHistory(suggestion, wasAccepted: false)
        
        // Remove from active suggestions
        removeSuggestion(suggestion)
    }
    
    /// Mark a suggestion as accepted
    /// - Parameter suggestion: The suggestion to mark
    private func markSuggestionAsAccepted(_ suggestion: HabitSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        
        suggestions[index].isAccepted = true
    }
    
    /// Remove a suggestion from the active list
    /// - Parameter suggestion: The suggestion to remove
    private func removeSuggestion(_ suggestion: HabitSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        saveSuggestions()
    }
    
    /// Record feedback on a suggestion
    /// - Parameters:
    ///   - suggestion: The suggestion to record feedback for
    ///   - isHelpful: Whether the suggestion was helpful
    ///   - comment: Optional comment from the user
    func recordSuggestionFeedback(
        suggestion: HabitSuggestion,
        isHelpful: Bool,
        comment: String? = nil
    ) {
        // Update user preferences based on feedback
        updateUserPreferences(for: suggestion.type, isHelpful: isHelpful)
        
        // Store feedback in history
        if let index = suggestionHistory.firstIndex(where: { $0.suggestionId == suggestion.id }) {
            suggestionHistory[index].wasHelpful = isHelpful
            suggestionHistory[index].userComment = comment
        }
        
        // Save updated preferences
        saveUserPreferences()
    }
    
    /// Add a suggestion to the history
    /// - Parameters:
    ///   - suggestion: The suggestion to add
    ///   - wasAccepted: Whether the suggestion was accepted
    private func addToSuggestionHistory(_ suggestion: HabitSuggestion, wasAccepted: Bool) {
        let historyItem = SuggestionHistoryItem(
            id: UUID(),
            suggestionId: suggestion.id,
            habitId: suggestion.habitId,
            type: suggestion.type,
            message: suggestion.message,
            createdAt: suggestion.createdAt,
            respondedAt: Date(),
            wasAccepted: wasAccepted,
            wasHelpful: nil,
            userComment: nil
        )
        
        suggestionHistory.append(historyItem)
        
        // Limit history size
        if suggestionHistory.count > 100 {
            suggestionHistory = Array(suggestionHistory.suffix(100))
        }
        
        // Save history
        saveSuggestionHistory()
    }
    
    // MARK: - Persistence
    
    /// Load saved suggestions
    private func loadSuggestions() {
        guard let data = UserDefaults.standard.data(forKey: "aiSuggestions") else { return }
        
        do {
            let decodedSuggestions = try JSONDecoder().decode([HabitSuggestion].self, from: data)
            suggestions = decodedSuggestions
        } catch {
            print("Failed to load suggestions: \(error)")
        }
    }
    
    /// Save current suggestions
    private func saveSuggestions() {
        do {
            let data = try JSONEncoder().encode(suggestions)
            UserDefaults.standard.set(data, forKey: "aiSuggestions")
        } catch {
            print("Failed to save suggestions: \(error)")
        }
    }
    
    /// Load suggestion history
    private func loadSuggestionHistory() {
        guard let data = UserDefaults.standard.data(forKey: "suggestionHistory") else { return }
        
        do {
            let decodedHistory = try JSONDecoder().decode([SuggestionHistoryItem].self, from: data)
            suggestionHistory = decodedHistory
        } catch {
            print("Failed to load suggestion history: \(error)")
        }
    }
    
    /// Save suggestion history
    private func saveSuggestionHistory() {
        do {
            let data = try JSONEncoder().encode(suggestionHistory)
            UserDefaults.standard.set(data, forKey: "suggestionHistory")
        } catch {
            print("Failed to save suggestion history: \(error)")
        }
    }
    
    /// Load user preferences
    private func loadUserPreferences() {
        guard let data = UserDefaults.standard.data(forKey: "aiUserPreferences") else { return }
        
        do {
            let decodedPreferences = try JSONDecoder().decode(UserPreferenceWeights.self, from: data)
            userPreferences = decodedPreferences
        } catch {
            print("Failed to load user preferences: \(error)")
        }
    }
    
    /// Save user preferences
    private func saveUserPreferences() {
        do {
            let data = try JSONEncoder().encode(userPreferences)
            UserDefaults.standard.set(data, forKey: "aiUserPreferences")
        } catch {
            print("Failed to save user preferences: \(error)")
        }
    }
    
    // MARK: - User Preferences and Learning
    
    /// Update user preferences based on feedback
    /// - Parameters:
    ///   - suggestionType: The type of suggestion
    ///   - isHelpful: Whether the suggestion was helpful
    private func updateUserPreferences(for suggestionType: SuggestionType, isHelpful: Bool) {
        // Adjust weight for this suggestion type
        let adjustmentFactor: Double = isHelpful ? 0.1 : -0.1
        
        switch suggestionType {
        case .timeOptimization:
            userPreferences.timeOptimizationWeight += adjustmentFactor
        case .frequencyAdjustment:
            userPreferences.frequencyAdjustmentWeight += adjustmentFactor
        case .streakMotivation:
            userPreferences.streakMotivationWeight += adjustmentFactor
        case .habitCombination:
            userPreferences.habitCombinationWeight += adjustmentFactor
        case .locationChange:
            userPreferences.locationChangeWeight += adjustmentFactor
        case .custom:
            userPreferences.customSuggestionWeight += adjustmentFactor
        }
        
        // Ensure weights stay within bounds
        userPreferences.normalizeWeights()
    }
    
    /// Learn from user behavior
    /// - Parameter habitManager: The habit manager to use for data
    func learnFromUserBehavior(_ habitManager: HabitManager? = nil) {
        // In a real implementation, this would analyze:
        // - Which suggestions were accepted vs. dismissed
        // - Which suggestions led to improved habit completion
        // - What times/days users complete habits most consistently
        
        // For the MVP, we'll just use the feedback mechanism
    }
    
    // MARK: - CoreML Integration (Future)
    
    /// Prepare ML model for future use
    private func prepareMLModel() {
        // In a real app, this would load a CoreML model
        // For the MVP, we'll use rule-based suggestions
    }
    
    /// Generate suggestion using ML model
    /// - Parameter habit: The habit to generate a suggestion for
    /// - Returns: A suggestion if one can be generated
    private func generateMLSuggestion(for habit: HabitViewModel) -> HabitSuggestion? {
        // This would use CoreML in a real implementation
        return nil
    }
    
    // MARK: - Scheduling and Observation
    
    /// Schedule regular analysis
    private func scheduleRegularAnalysis() {
        // Analyze once a day
        let timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.generateSuggestions()
        }
        
        // Keep timer active
        RunLoop.current.add(timer, forMode: .common)
    }
    
    /// Observe changes in habits
    private func observeHabitChanges() {
        NotificationCenter.default.publisher(for: .habitDataChanged)
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.generateSuggestions()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Helper Methods
    
    /// Format a time of day string
    /// - Parameter date: The date to format
    /// - Returns: Formatted string (e.g., "morning", "afternoon")
    private func formatTimeOfDay(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        
        switch hour {
        case 5..<12:
            return "morning"
        case 12..<17:
            return "afternoon"
        case 17..<21:
            return "evening"
        default:
            return "night"
        }
    }
    
    /// Format a time string
    /// - Parameter date: The date to format
    /// - Returns: Formatted string (e.g., "8:00 AM")
    private func formatTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
