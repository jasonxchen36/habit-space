import CoreData
import SwiftUI

class CoreDataManager {
    static let shared = CoreDataManager()
    
    let container: NSPersistentContainer
    let context: NSManagedObjectContext
    
    private init() {
        container = NSPersistentContainer(name: "HabitSpace")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error.localizedDescription)")
            }
        }
        context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
    }
    
    // MARK: - Save Context
    func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // MARK: - Habit Operations
    func createHabit(name: String, iconName: String, targetCount: Int16 = 1) -> Habit {
        let habit = Habit(context: context)
        habit.id = UUID()
        habit.name = name
        habit.iconName = iconName
        habit.createdAt = Date()
        habit.isActive = true
        habit.targetCount = targetCount
        habit.currentStreak = 0
        habit.bestStreak = 0
        saveContext()
        return habit
    }
    
    func fetchHabits() -> [Habit] {
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Habit.createdAt, ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching habits: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Habit Completion Operations
    func completeHabit(_ habit: Habit, notes: String? = nil) {
        let completion = HabitCompletion(context: context)
        completion.id = UUID()
        completion.timestamp = Date()
        completion.notes = notes
        completion.habit = habit
        
        // Update streak logic
        habit.currentStreak += 1
        if habit.currentStreak > habit.bestStreak {
            habit.bestStreak = habit.currentStreak
        }
        
        saveContext()
    }
    
    // MARK: - AR Anchor Operations
    func saveARAnchor(for habit: Habit, anchorIdentifier: String, position: SIMD3<Float>, rotation: simd_quatf) {
        guard let habitId = habit.id else { return }
        
        // Check if anchor already exists for this habit
        let fetchRequest: NSFetchRequest<ARAnchorEntity> = ARAnchorEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "habitId == %@", habitId as CVarArg)
        
        let anchor: ARAnchorEntity
        
        if let existingAnchor = try? context.fetch(fetchRequest).first {
            anchor = existingAnchor
        } else {
            anchor = ARAnchorEntity(context: context)
            anchor.id = UUID()
            anchor.habitId = habitId
            anchor.createdAt = Date()
        }
        
        anchor.anchorIdentifier = anchorIdentifier
        anchor.positionX = Double(position.x)
        anchor.positionY = Double(position.y)
        anchor.positionZ = Double(position.z)
        
        let eulerAngles = rotation.eulerAngles
        anchor.rotationX = Double(eulerAngles.x)
        anchor.rotationY = Double(eulerAngles.y)
        anchor.rotationZ = Double(eulerAngles.z)
        
        saveContext()
    }
    
    func getARAnchor(for habit: Habit) -> ARAnchorEntity? {
        guard let habitId = habit.id else { return nil }
        
        let request: NSFetchRequest<ARAnchorEntity> = ARAnchorEntity.fetchRequest()
        request.predicate = NSPredicate(format: "habitId == %@", habitId as CVarArg)
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching AR anchor: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Preview Helper
#if DEBUG
extension CoreDataManager {
    static var preview: CoreDataManager = {
        let result = CoreDataManager()
        let viewContext = result.container.viewContext
        
        // Create sample habits
        let habit1 = Habit(context: viewContext)
        habit1.id = UUID()
        habit1.name = "Drink Water"
        habit1.iconName = "drop.fill"
        habit1.createdAt = Date()
        habit1.isActive = true
        habit1.targetCount = 8
        habit1.currentStreak = 5
        habit1.bestStreak = 10
        
        let habit2 = Habit(context: viewContext)
        habit2.id = UUID()
        habit2.name = "Meditate"
        habit2.iconName = "leaf.fill"
        habit2.createdAt = Date()
        habit2.isActive = true
        habit2.targetCount = 1
        habit2.currentStreak = 3
        habit2.bestStreak = 7
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()
}
#endif
