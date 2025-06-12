import Foundation
import CoreData
import Combine

/// CoreDataManager is responsible for managing the Core Data stack and providing
/// methods for interacting with the persistent store.
class CoreDataManager {
    // MARK: - Singleton
    
    /// Shared instance of the CoreDataManager
    static let shared = CoreDataManager()
    
    /// Private initializer to enforce singleton pattern
    private init() {
        // Register for app termination notification to save context
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveContextIfNeeded),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    // MARK: - Core Data Stack
    
    /// The persistent container for the application
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "HabitSpace")
        
        // Configure persistent store options
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [storeDescription]
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // Log error and present user-facing alert in production app
                fatalError("Persistent store failed to load: \(error), \(error.userInfo)")
            }
        }
        
        // Configure automatic merging of changes from parent contexts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    /// The main view context for the application
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    /// Creates a new background context for performing operations off the main thread
    /// - Returns: A new NSManagedObjectContext with a private queue concurrency type
    func createBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - Core Data Saving Support
    
    /// Saves changes in the view context if there are changes to save
    /// - Returns: Boolean indicating success or failure
    @discardableResult
    func saveContext() -> Bool {
        return saveContext(viewContext)
    }
    
    /// Saves changes in the specified context if there are changes to save
    /// - Parameter context: The NSManagedObjectContext to save
    /// - Returns: Boolean indicating success or failure
    @discardableResult
    func saveContext(_ context: NSManagedObjectContext) -> Bool {
        if context.hasChanges {
            do {
                try context.save()
                return true
            } catch {
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
                // In a production app, we would log this error and potentially present a user-facing alert
                return false
            }
        }
        return true // No changes to save, so technically successful
    }
    
    /// Save the view context if needed (called when app is terminating)
    @objc private func saveContextIfNeeded() {
        saveContext()
    }
    
    /// Performs a block on a background context and saves the context
    /// - Parameter block: The block to perform on the background context
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let context = createBackgroundContext()
        context.perform {
            block(context)
            self.saveContext(context)
        }
    }
    
    /// Performs a block on a background context and saves the context, with completion handler
    /// - Parameters:
    ///   - block: The block to perform on the background context
    ///   - completion: Completion handler called when the operation is done
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void, completion: @escaping (Bool) -> Void) {
        let context = createBackgroundContext()
        context.perform {
            block(context)
            let success = self.saveContext(context)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    // MARK: - Habit Operations
    
    /// Creates a new habit
    /// - Parameters:
    ///   - title: The title of the habit
    ///   - frequency: The frequency of the habit (daily, weekly, etc.)
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The created habit
    func createHabit(
        title: String,
        frequency: String,
        context: NSManagedObjectContext? = nil
    ) -> Habit {
        let context = context ?? viewContext
        let habit = Habit(context: context)
        
        habit.id = UUID()
        habit.title = title
        habit.frequency = frequency
        habit.createdAt = Date()
        habit.streak = 0
        habit.isActive = true
        
        return habit
    }
    
    /// Fetches all habits
    /// - Parameters:
    ///   - predicate: Optional predicate to filter habits
    ///   - sortDescriptors: Optional sort descriptors
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of habits
    func fetchHabits(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        context: NSManagedObjectContext? = nil
    ) -> [Habit] {
        let context = context ?? viewContext
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors ?? [
            NSSortDescriptor(keyPath: \Habit.createdAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching habits: \(error)")
            return []
        }
    }
    
    /// Fetches a habit by ID
    /// - Parameters:
    ///   - id: The UUID of the habit
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The habit if found, nil otherwise
    func fetchHabit(
        withID id: UUID,
        context: NSManagedObjectContext? = nil
    ) -> Habit? {
        let context = context ?? viewContext
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching habit with ID \(id): \(error)")
            return nil
        }
    }
    
    /// Deletes a habit
    /// - Parameters:
    ///   - habit: The habit to delete
    ///   - context: Optional context to use (defaults to viewContext)
    func deleteHabit(
        _ habit: Habit,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? viewContext
        
        // Delete associated anchors
        if let anchors = habit.anchors as? Set<Anchor> {
            for anchor in anchors {
                context.delete(anchor)
            }
        }
        
        // Delete associated log entries
        if let logEntries = habit.logEntries as? Set<LogEntry> {
            for logEntry in logEntries {
                context.delete(logEntry)
            }
        }
        
        // Delete associated suggestions
        if let suggestions = habit.suggestions as? Set<Suggestion> {
            for suggestion in suggestions {
                context.delete(suggestion)
            }
        }
        
        // Delete the habit
        context.delete(habit)
    }
    
    // MARK: - Anchor Operations
    
    /// Creates a new anchor for a habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - worldTransform: The transform data for AR positioning
    ///   - iconType: The type of icon to display
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The created anchor
    func createAnchor(
        habitID: UUID,
        worldTransform: Data,
        iconType: String,
        context: NSManagedObjectContext? = nil
    ) -> Anchor {
        let context = context ?? viewContext
        let anchor = Anchor(context: context)
        
        anchor.id = UUID()
        anchor.habitID = habitID
        anchor.worldTransform = worldTransform
        anchor.iconType = iconType
        anchor.createdAt = Date()
        anchor.isActive = true
        
        // Link to habit
        if let habit = fetchHabit(withID: habitID, context: context) {
            anchor.habit = habit
        }
        
        return anchor
    }
    
    /// Fetches all anchors
    /// - Parameters:
    ///   - predicate: Optional predicate to filter anchors
    ///   - sortDescriptors: Optional sort descriptors
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of anchors
    func fetchAnchors(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        context: NSManagedObjectContext? = nil
    ) -> [Anchor] {
        let context = context ?? viewContext
        let request: NSFetchRequest<Anchor> = Anchor.fetchRequest()
        
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors ?? [
            NSSortDescriptor(keyPath: \Anchor.createdAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching anchors: \(error)")
            return []
        }
    }
    
    /// Fetches anchors for a specific habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - activeOnly: Whether to fetch only active anchors
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of anchors
    func fetchAnchors(
        forHabitID habitID: UUID,
        activeOnly: Bool = true,
        context: NSManagedObjectContext? = nil
    ) -> [Anchor] {
        let context = context ?? viewContext
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "habitID == %@", habitID as CVarArg)
        ]
        
        if activeOnly {
            predicates.append(NSPredicate(format: "isActive == YES"))
        }
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        return fetchAnchors(
            predicate: compoundPredicate,
            context: context
        )
    }
    
    /// Deletes an anchor
    /// - Parameters:
    ///   - anchor: The anchor to delete
    ///   - context: Optional context to use (defaults to viewContext)
    func deleteAnchor(
        _ anchor: Anchor,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? viewContext
        context.delete(anchor)
    }
    
    // MARK: - LogEntry Operations
    
    /// Creates a new log entry for a habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - status: The status of the completion (completed, skipped, etc.)
    ///   - completedAt: The date of completion
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The created log entry
    func createLogEntry(
        habitID: UUID,
        status: String,
        completedAt: Date = Date(),
        context: NSManagedObjectContext? = nil
    ) -> LogEntry {
        let context = context ?? viewContext
        let logEntry = LogEntry(context: context)
        
        logEntry.id = UUID()
        logEntry.habitID = habitID
        logEntry.status = status
        logEntry.completedAt = completedAt
        
        // Link to habit
        if let habit = fetchHabit(withID: habitID, context: context) {
            logEntry.habit = habit
        }
        
        return logEntry
    }
    
    /// Fetches log entries for a specific habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - startDate: Optional start date to filter entries
    ///   - endDate: Optional end date to filter entries
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of log entries
    func fetchLogEntries(
        forHabitID habitID: UUID,
        startDate: Date? = nil,
        endDate: Date? = nil,
        context: NSManagedObjectContext? = nil
    ) -> [LogEntry] {
        let context = context ?? viewContext
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "habitID == %@", habitID as CVarArg)
        ]
        
        if let startDate = startDate {
            predicates.append(NSPredicate(format: "completedAt >= %@", startDate as NSDate))
        }
        
        if let endDate = endDate {
            predicates.append(NSPredicate(format: "completedAt <= %@", endDate as NSDate))
        }
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        request.predicate = compoundPredicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LogEntry.completedAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching log entries: \(error)")
            return []
        }
    }
    
    /// Fetches log entries for a specific date range
    /// - Parameters:
    ///   - startDate: The start date
    ///   - endDate: The end date
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of log entries
    func fetchLogEntries(
        fromDate startDate: Date,
        toDate endDate: Date,
        context: NSManagedObjectContext? = nil
    ) -> [LogEntry] {
        let context = context ?? viewContext
        
        let predicate = NSPredicate(
            format: "completedAt >= %@ AND completedAt <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let request: NSFetchRequest<LogEntry> = LogEntry.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LogEntry.completedAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching log entries: \(error)")
            return []
        }
    }
    
    /// Deletes a log entry
    /// - Parameters:
    ///   - logEntry: The log entry to delete
    ///   - context: Optional context to use (defaults to viewContext)
    func deleteLogEntry(
        _ logEntry: LogEntry,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? viewContext
        context.delete(logEntry)
    }
    
    // MARK: - Suggestion Operations
    
    /// Creates a new suggestion for a habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - message: The suggestion message
    ///   - suggestedTime: Optional suggested time
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The created suggestion
    func createSuggestion(
        habitID: UUID,
        message: String,
        suggestedTime: Date? = nil,
        context: NSManagedObjectContext? = nil
    ) -> Suggestion {
        let context = context ?? viewContext
        let suggestion = Suggestion(context: context)
        
        suggestion.id = UUID()
        suggestion.habitID = habitID
        suggestion.message = message
        suggestion.suggestedTime = suggestedTime
        suggestion.isAccepted = false
        suggestion.createdAt = Date()
        
        // Link to habit
        if let habit = fetchHabit(withID: habitID, context: context) {
            suggestion.habit = habit
        }
        
        return suggestion
    }
    
    /// Fetches suggestions for a specific habit
    /// - Parameters:
    ///   - habitID: The UUID of the habit
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of suggestions
    func fetchSuggestions(
        forHabitID habitID: UUID,
        context: NSManagedObjectContext? = nil
    ) -> [Suggestion] {
        let context = context ?? viewContext
        
        let predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        
        let request: NSFetchRequest<Suggestion> = Suggestion.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Suggestion.createdAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching suggestions: \(error)")
            return []
        }
    }
    
    /// Fetches all active (not accepted) suggestions
    /// - Parameter context: Optional context to use (defaults to viewContext)
    /// - Returns: Array of suggestions
    func fetchActiveSuggestions(
        context: NSManagedObjectContext? = nil
    ) -> [Suggestion] {
        let context = context ?? viewContext
        
        let predicate = NSPredicate(format: "isAccepted == NO")
        
        let request: NSFetchRequest<Suggestion> = Suggestion.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Suggestion.createdAt, ascending: false)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching active suggestions: \(error)")
            return []
        }
    }
    
    /// Marks a suggestion as accepted
    /// - Parameters:
    ///   - suggestion: The suggestion to mark
    ///   - context: Optional context to use (defaults to viewContext)
    func acceptSuggestion(
        _ suggestion: Suggestion,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? viewContext
        suggestion.isAccepted = true
    }
    
    /// Deletes a suggestion
    /// - Parameters:
    ///   - suggestion: The suggestion to delete
    ///   - context: Optional context to use (defaults to viewContext)
    func deleteSuggestion(
        _ suggestion: Suggestion,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? viewContext
        context.delete(suggestion)
    }
    
    // MARK: - Batch Operations
    
    /// Performs a batch delete operation
    /// - Parameters:
    ///   - entityName: The name of the entity to delete from
    ///   - predicate: The predicate to filter entities
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The number of objects deleted
    @discardableResult
    func batchDelete(
        entityName: String,
        predicate: NSPredicate,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let context = context ?? viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        do {
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            let objectIDs = result?.result as? [NSManagedObjectID] ?? []
            
            // Merge changes into context
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            
            return objectIDs.count
        } catch {
            print("Error performing batch delete: \(error)")
            return 0
        }
    }
    
    /// Performs a batch update operation
    /// - Parameters:
    ///   - entityName: The name of the entity to update
    ///   - predicate: The predicate to filter entities
    ///   - propertiesToUpdate: Dictionary of properties to update
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: The number of objects updated
    @discardableResult
    func batchUpdate(
        entityName: String,
        predicate: NSPredicate,
        propertiesToUpdate: [String: Any],
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let context = context ?? viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        
        let updateRequest = NSBatchUpdateRequest(fetchRequest: fetchRequest)
        updateRequest.propertiesToUpdate = propertiesToUpdate
        updateRequest.resultType = .updatedObjectIDsResultType
        
        do {
            let result = try context.execute(updateRequest) as? NSBatchUpdateResult
            let objectIDs = result?.result as? [NSManagedObjectID] ?? []
            
            // Merge changes into context
            let changes = [NSUpdatedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            
            return objectIDs.count
        } catch {
            print("Error performing batch update: \(error)")
            return 0
        }
    }
    
    // MARK: - Error Handling
    
    /// Handles a Core Data error
    /// - Parameter error: The error to handle
    /// - Returns: A user-friendly error message
    func handleCoreDataError(_ error: Error) -> String {
        let nsError = error as NSError
        
        // Log the error
        print("Core Data error: \(nsError), \(nsError.userInfo)")
        
        // Check for specific error codes
        switch nsError.code {
        case NSCoreDataError:
            return "A Core Data error occurred."
        case NSValidationErrorMinimum..<NSValidationErrorMaximum:
            return "The data is invalid. Please check your input."
        case NSManagedObjectConstraintMergeError:
            return "A constraint error occurred."
        case NSPersistentStoreError:
            return "There was a problem with the data store."
        default:
            return "An unexpected error occurred. Please try again."
        }
    }
    
    // MARK: - Utility Methods
    
    /// Checks if an entity exists with a specific attribute value
    /// - Parameters:
    ///   - entityName: The name of the entity
    ///   - attributeName: The name of the attribute
    ///   - value: The value to check for
    ///   - context: Optional context to use (defaults to viewContext)
    /// - Returns: Whether an entity exists with the specified attribute value
    func entityExists(
        entityName: String,
        attributeName: String,
        value: Any,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", attributeName, value as! CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            let count = try context.count(for: fetchRequest)
            return count > 0
        } catch {
            print("Error checking if entity exists: \(error)")
            return false
        }
    }
    
    /// Resets the Core Data stack
    /// - Warning: This will delete all data in the persistent store
    func resetCoreData() {
        // Remove the persistent store
        guard let storeCoordinator = persistentContainer.persistentStoreCoordinator else {
            return
        }
        
        for store in storeCoordinator.persistentStores {
            do {
                try storeCoordinator.remove(store)
            } catch {
                print("Error removing persistent store: \(error)")
            }
        }
        
        // Delete the store file
        guard let storeURL = storeCoordinator.persistentStores.first?.url else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: storeURL)
        } catch {
            print("Error removing store file: \(error)")
        }
        
        // Recreate the persistent container
        let container = NSPersistentContainer(name: "HabitSpace")
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Failed to recreate persistent store: \(error), \(error.userInfo)")
            }
        }
        
        // Update the persistent container
        self.persistentContainer = container
    }
    
    // MARK: - Debug Methods
    
    #if DEBUG
    /// Prints the contents of the persistent store for debugging
    func printStoreContents() {
        let habits = fetchHabits()
        print("--- HABITS ---")
        for habit in habits {
            print("Habit: \(habit.title ?? "Unnamed"), ID: \(habit.id?.uuidString ?? "No ID")")
            
            if let anchors = habit.anchors as? Set<Anchor>, !anchors.isEmpty {
                print("  Anchors:")
                for anchor in anchors {
                    print("    Anchor ID: \(anchor.id?.uuidString ?? "No ID")")
                }
            }
            
            if let logEntries = habit.logEntries as? Set<LogEntry>, !logEntries.isEmpty {
                print("  Log Entries:")
                for entry in logEntries {
                    print("    Entry: \(entry.completedAt ?? Date()), Status: \(entry.status ?? "Unknown")")
                }
            }
            
            if let suggestions = habit.suggestions as? Set<Suggestion>, !suggestions.isEmpty {
                print("  Suggestions:")
                for suggestion in suggestions {
                    print("    Suggestion: \(suggestion.message ?? "No message")")
                }
            }
        }
    }
    
    /// Creates sample data for testing
    func createSampleData() {
        // Create sample habits
        let habit1 = createHabit(title: "Drink Water", frequency: "daily")
        let habit2 = createHabit(title: "Meditate", frequency: "daily")
        let habit3 = createHabit(title: "Exercise", frequency: "weekly")
        
        // Create sample log entries
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        
        _ = createLogEntry(habitID: habit1.id!, status: "completed", completedAt: today)
        _ = createLogEntry(habitID: habit1.id!, status: "completed", completedAt: yesterday)
        _ = createLogEntry(habitID: habit1.id!, status: "completed", completedAt: twoDaysAgo)
        
        _ = createLogEntry(habitID: habit2.id!, status: "completed", completedAt: today)
        _ = createLogEntry(habitID: habit2.id!, status: "skipped", completedAt: yesterday)
        
        _ = createLogEntry(habitID: habit3.id!, status: "completed", completedAt: yesterday)
        
        // Create sample suggestions
        _ = createSuggestion(
            habitID: habit1.id!,
            message: "Try drinking water first thing in the morning"
        )
        
        _ = createSuggestion(
            habitID: habit2.id!,
            message: "Meditate in a quiet space for better focus",
            suggestedTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: today)
        )
        
        // Save context
        saveContext()
    }
    #endif
}
