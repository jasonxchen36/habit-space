import SwiftUI
import CoreData
import UserNotifications
import ARKit
import Combine
import RealityKit
import HealthKit

@main
struct HabitSpaceApp: App {
    // MARK: - State Objects
    
    /// Main managers for the application
    @StateObject private var habitManager = HabitManager()
    @StateObject private var anchorManager = AnchorManager()
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var aiManager = AIManager()
    
    /// Optional HealthKit manager for future health data integration
    @StateObject private var healthManager = HealthManager()
    
    /// Tracks current app state
    @Environment(\.scenePhase) private var scenePhase
    
    /// Controls whether onboarding is shown
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // MARK: - Core Data
    
    /// Shared Core Data persistence controller
    let persistenceController = PersistenceController.shared
    
    // MARK: - App Body
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(habitManager)
                .environmentObject(anchorManager)
                .environmentObject(notificationManager)
                .environmentObject(aiManager)
                .environmentObject(healthManager)
                .onAppear {
                    setupApp()
                }
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
        
        #if os(visionOS)
        // Additional immersive space for visionOS
        ImmersiveSpace(id: "ar-space") {
            ARImmersiveView()
                .environmentObject(habitManager)
                .environmentObject(anchorManager)
        }
        #endif
    }
    
    // MARK: - Setup Methods
    
    /// Initialize app components and request permissions
    private func setupApp() {
        // Request notification permissions
        requestNotificationPermissions()
        
        // Initialize managers with CoreData context
        habitManager.initialize(context: persistenceController.container.viewContext)
        anchorManager.initialize(context: persistenceController.container.viewContext)
        notificationManager.initialize(habitManager: habitManager, anchorManager: anchorManager)
        aiManager.initialize(habitManager: habitManager)
        healthManager.initialize()
        
        // Connect managers to each other for cross-communication
        anchorManager.setHabitManager(habitManager)
        
        // Check if first launch for onboarding
        checkFirstLaunch()
    }
    
    /// Request notification permissions from the user
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permissions granted")
            } else if let error = error {
                print("Notification permissions error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check if this is the first app launch
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            // First launch - set app state for onboarding
            habitManager.isFirstLaunch = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }
    
    /// Handle app lifecycle phase changes
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active
            anchorManager.resumeARSession()
            notificationManager.refreshNotifications()
            healthManager.refreshHealthData()
        case .inactive:
            // App became inactive
            persistenceController.save()
        case .background:
            // App went to background
            persistenceController.save()
            anchorManager.pauseARSession()
            
            // Schedule background tasks if needed
            scheduleBackgroundTasks()
        @unknown default:
            break
        }
    }
    
    /// Schedule background tasks for when app is in background
    private func scheduleBackgroundTasks() {
        // Schedule proximity checks or other background work
        // This would use BGTaskScheduler in a production app
    }
}

// MARK: - Persistence Controller
struct PersistenceController {
    /// Shared instance for app-wide use
    static let shared = PersistenceController()
    
    /// Core Data container
    let container: NSPersistentContainer
    
    /// Initialize the persistence controller
    /// - Parameter inMemory: Whether to use in-memory store (for previews/testing)
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "HabitSpace")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error loading Core Data stores: \(error.localizedDescription)")
            }
        }
        
        // Enable automatic merging of changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    /// Save the Core Data context if there are changes
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Error saving Core Data context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @EnvironmentObject private var habitManager: HabitManager
    
    var body: some View {
        if !hasCompletedOnboarding || habitManager.isFirstLaunch {
            OnboardingView()
        } else {
            MainTabView()
        }
    }
}

// MARK: - visionOS Immersive View
#if os(visionOS)
struct ARImmersiveView: View {
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var anchorManager: AnchorManager
    
    var body: some View {
        RealityView { content in
            // Configure visionOS AR content
            // This will be expanded in the future for Apple Vision Pro
        }
    }
}
#endif

// MARK: - Health Manager
/// Manages HealthKit integration (placeholder for future implementation)
class HealthManager: ObservableObject {
    private var healthStore: HKHealthStore?
    
    func initialize() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
            requestHealthKitPermissions()
        }
    }
    
    private func requestHealthKitPermissions() {
        guard let healthStore = healthStore else { return }
        
        // Define the health data types to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ].compactMap { $0 }
        
        // Request authorization
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if !success {
                print("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    func refreshHealthData() {
        // This would fetch updated health data when the app becomes active
    }
}
