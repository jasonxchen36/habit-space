import SwiftUI
import CoreData
import Combine
import ARKit
import RealityKit

// MARK: - Frequency Enums

/// Frequency options for habits
enum HabitFrequency: String, CaseIterable, Identifiable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
    
    var description: String {
        switch self {
        case .daily: return "Every day"
        case .weekly: return "Once a week"
        case .monthly: return "Once a month"
        }
    }
    
    var icon: String {
        switch self {
        case .daily: return "calendar.day.timeline.left"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        }
    }
}

/// Status options for habit completion
enum HabitStatus: String, Codable {
    case completed = "completed"
    case skipped = "skipped"
    case missed = "missed"
    
    var icon: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .missed: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .completed: return .green
        case .skipped: return .orange
        case .missed: return .red
        }
    }
}

// MARK: - AR Types

/// Types of anchor icons for AR placement
enum AnchorIconType: String, CaseIterable, Identifiable, Codable {
    case glow = "glow"
    case emoji = "emoji"
    case model3D = "model3D"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .glow: return "Glowing Dot"
        case .emoji: return "Emoji Icon"
        case .model3D: return "3D Model"
        }
    }
    
    var previewImage: String {
        switch self {
        case .glow: return "circle.fill"
        case .emoji: return "face.smiling"
        case .model3D: return "cube.fill"
        }
    }
}

/// AR session states
enum ARSessionState: String {
    case initializing
    case running
    case paused
    case limited
    case failed
    case interrupted
    
    var description: String {
        switch self {
        case .initializing: return "Initializing AR..."
        case .running: return "AR Running"
        case .paused: return "AR Paused"
        case .limited: return "Limited Tracking"
        case .failed: return "AR Failed"
        case .interrupted: return "AR Interrupted"
        }
    }
}

// MARK: - Notification Types

/// Notification type categories
enum NotificationType: String, Codable {
    case proximity = "proximity"
    case time = "time"
    case reminder = "reminder"
    case system = "system"
}

/// Notification category identifiers
enum NotificationCategoryIdentifier: String {
    case habitReminder = "HABIT_REMINDER"
}

/// Notification action identifiers
enum NotificationActionIdentifier: String {
    case complete = "COMPLETE_ACTION"
    case skip = "SKIP_ACTION"
    case snooze = "SNOOZE_ACTION"
}

// MARK: - View Models

/// View model for a habit
struct HabitViewModel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let frequency: String
    let streak: Int
    let isActive: Bool
    let createdDate: Date?
    
    var isCompletedToday: Bool = false
    var isSkippedToday: Bool = false
    var isMissedToday: Bool = false
    
    var color: Color {
        // Generate consistent color based on title
        let hash = title.hash
        let hue = Double(abs(hash) % 10) / 10.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    var icon: String {
        // Default icons based on habit title
        if title.lowercased().contains("water") {
            return "drop.fill"
        } else if title.lowercased().contains("exercise") || title.lowercased().contains("workout") {
            return "figure.run"
        } else if title.lowercased().contains("read") {
            return "book.fill"
        } else if title.lowercased().contains("meditate") || title.lowercased().contains("mindful") {
            return "brain.head.profile"
        } else if title.lowercased().contains("sleep") {
            return "bed.double.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    init(habit: Habit) {
        self.id = habit.id ?? UUID()
        self.title = habit.title ?? "Untitled Habit"
        self.frequency = habit.frequency ?? HabitFrequency.daily.rawValue
        self.streak = Int(habit.streak)
        self.isActive = habit.isActive
        self.createdDate = habit.createdAt
        
        // Check if completed today
        if let logEntries = habit.logEntries as? Set<LogEntry> {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            
            for entry in logEntries {
                guard let completedAt = entry.completedAt,
                      completedAt >= today && completedAt < tomorrow else { continue }
                
                if entry.status == HabitStatus.completed.rawValue {
                    isCompletedToday = true
                } else if entry.status == HabitStatus.skipped.rawValue {
                    isSkippedToday = true
                } else if entry.status == HabitStatus.missed.rawValue {
                    isMissedToday = true
                }
            }
        }
    }
    
    static func == (lhs: HabitViewModel, rhs: HabitViewModel) -> Bool {
        return lhs.id == rhs.id
    }
}

/// View model for an AR anchor
struct AnchorViewModel: Identifiable, Equatable {
    let id: UUID
    let habitId: UUID
    let worldTransform: simd_float4x4
    let iconType: AnchorIconType
    let createdDate: Date?
    let isActive: Bool
    
    init(anchor: Anchor, transform: simd_float4x4) {
        self.id = anchor.id ?? UUID()
        self.habitId = anchor.habitID ?? UUID()
        self.worldTransform = transform
        self.iconType = AnchorIconType(rawValue: anchor.iconType ?? "glow") ?? .glow
        self.createdDate = anchor.createdAt
        self.isActive = anchor.isActive
    }
    
    static func == (lhs: AnchorViewModel, rhs: AnchorViewModel) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Data representation for log entries
struct LogEntryData: Identifiable {
    let id: UUID
    let habitId: UUID
    let completedAt: Date
    let status: String
}

// MARK: - Suggestion Types

/// Types of AI suggestions
enum SuggestionType: String, Codable, CaseIterable {
    case timeOptimization = "timeOptimization"
    case frequencyAdjustment = "frequencyAdjustment"
    case streakMotivation = "streakMotivation"
    case habitCombination = "habitCombination"
    case locationChange = "locationChange"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .timeOptimization: return "Time Optimization"
        case .frequencyAdjustment: return "Frequency Adjustment"
        case .streakMotivation: return "Streak Motivation"
        case .habitCombination: return "Habit Combination"
        case .locationChange: return "Location Change"
        case .custom: return "Custom Suggestion"
        }
    }
    
    var icon: String {
        switch self {
        case .timeOptimization: return "clock.fill"
        case .frequencyAdjustment: return "calendar.badge.plus"
        case .streakMotivation: return "flame.fill"
        case .habitCombination: return "link.circle.fill"
        case .locationChange: return "location.fill"
        case .custom: return "lightbulb.fill"
        }
    }
}

/// Habit suggestion model
struct HabitSuggestion: Identifiable, Codable {
    let id: UUID
    let habitId: UUID
    let title: String
    let message: String
    let type: SuggestionType
    let suggestedTime: Date?
    let suggestedFrequency: HabitFrequency?
    let relatedHabitId: UUID?
    let priority: Double
    var isAccepted: Bool
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        habitId: UUID,
        title: String,
        message: String,
        type: SuggestionType,
        suggestedTime: Date? = nil,
        suggestedFrequency: HabitFrequency? = nil,
        relatedHabitId: UUID? = nil,
        priority: Double = 0.5,
        isAccepted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.habitId = habitId
        self.title = title
        self.message = message
        self.type = type
        self.suggestedTime = suggestedTime
        self.suggestedFrequency = suggestedFrequency
        self.relatedHabitId = relatedHabitId
        self.priority = priority
        self.isAccepted = isAccepted
        self.createdAt = createdAt
    }
}

/// Suggestion template for AI
struct SuggestionTemplate {
    let type: SuggestionType
    let titleTemplate: String
    let messageTemplate: String
    let priority: Double
}

/// Suggestion history item
struct SuggestionHistoryItem: Identifiable, Codable {
    let id: UUID
    let suggestionId: UUID
    let habitId: UUID
    let type: SuggestionType
    let message: String
    let createdAt: Date
    let respondedAt: Date
    let wasAccepted: Bool
    var wasHelpful: Bool?
    var userComment: String?
}

// MARK: - Notification Models

/// Notification settings model
struct NotificationSettings: Codable {
    /// Whether notifications are enabled
    var isEnabled: Bool = true
    
    /// Whether to show notification banners when app is active
    var showBannerWhenActive: Bool = true
    
    /// Whether to enable notification sounds
    var soundEnabled: Bool = true
    
    /// Whether to enable notification badges
    var badgesEnabled: Bool = true
    
    /// Proximity radius for anchor notifications (in meters)
    var proximityRadius: Double = 2.0
    
    /// Minimum interval between notifications for the same habit (in seconds)
    var minimumNotificationInterval: TimeInterval = 3600 // 1 hour
    
    /// Whether to enable default time-based reminders
    var defaultReminderEnabled: Bool = false
    
    /// Default reminder time
    var defaultReminderTime: Date = Calendar.current.date(
        bySettingHour: 18, 
        minute: 0, 
        second: 0, 
        of: Date()
    ) ?? Date()
}

/// Notification history item
struct NotificationHistoryItem: Identifiable {
    let id: UUID
    let habitId: UUID
    let anchorId: UUID?
    let timestamp: Date
    let type: NotificationType
}

// MARK: - Onboarding Models

/// Template for creating new habits during onboarding
struct HabitTemplate: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let frequency: HabitFrequency
    let iconName: String
    let suggestedAnchors: [String]
    
    var color: Color {
        // Generate consistent color based on title
        let hash = title.hash
        let hue = Double(abs(hash) % 10) / 10.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
}

// MARK: - Analytics Models

/// Habit insight model for analytics
struct HabitInsight: Identifiable, Codable {
    let id: UUID
    let habitId: UUID
    let title: String
    let description: String
    let dataPoints: [String: Double]
    let createdAt: Date
}

/// Habit pattern model for AI analysis
struct HabitPattern {
    let habitId: UUID
    let habitTitle: String
    let completionRate: Double
    let optimalTimeOfDay: Date?
    let currentFrequency: HabitFrequency
    let suggestedFrequency: HabitFrequency?
    let streak: Int
    let isStreakAtRisk: Bool
    let missedDaysPattern: [Int]
    let relatedHabits: [HabitViewModel]
}

/// User preference weights for AI suggestions
struct UserPreferenceWeights: Codable {
    var timeOptimizationWeight: Double = 1.0
    var frequencyAdjustmentWeight: Double = 1.0
    var streakMotivationWeight: Double = 1.0
    var habitCombinationWeight: Double = 1.0
    var locationChangeWeight: Double = 1.0
    var customSuggestionWeight: Double = 1.0
    
    /// Normalize weights to ensure they stay within bounds
    mutating func normalizeWeights() {
        timeOptimizationWeight = max(0.1, min(2.0, timeOptimizationWeight))
        frequencyAdjustmentWeight = max(0.1, min(2.0, frequencyAdjustmentWeight))
        streakMotivationWeight = max(0.1, min(2.0, streakMotivationWeight))
        habitCombinationWeight = max(0.1, min(2.0, habitCombinationWeight))
        locationChangeWeight = max(0.1, min(2.0, locationChangeWeight))
        customSuggestionWeight = max(0.1, min(2.0, customSuggestionWeight))
    }
}

// MARK: - Deep Link Models

/// Deep link destination types
enum DeepLinkDestination {
    case habit(UUID)
    case anchor(UUID)
    case suggestion(UUID)
}

// MARK: - Value Transformer for simd_float4x4

/// Value transformer for storing simd_float4x4 in Core Data
@objc(WorldTransformValueTransformer)
class WorldTransformValueTransformer: NSSecureUnarchiveFromDataTransformer {
    override class var allowedTopLevelClasses: [AnyClass] {
        return super.allowedTopLevelClasses + [NSValue.self]
    }
    
    static func register() {
        let transformer = WorldTransformValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: NSValueTransformerName("WorldTransformValueTransformer"))
    }
}

// MARK: - Default Data

/// Provides default data for the app
struct DefaultData {
    /// Default habit templates for onboarding
    static let habitTemplates: [HabitTemplate] = [
        HabitTemplate(
            title: "Drink Water",
            description: "Stay hydrated throughout the day",
            frequency: .daily,
            iconName: "drop.fill",
            suggestedAnchors: ["Water bottle", "Kitchen sink", "Refrigerator"]
        ),
        HabitTemplate(
            title: "Meditate",
            description: "Take time for mindfulness and mental clarity",
            frequency: .daily,
            iconName: "brain.head.profile",
            suggestedAnchors: ["Favorite chair", "Bed", "Yoga mat"]
        ),
        HabitTemplate(
            title: "Exercise",
            description: "Stay active and maintain physical health",
            frequency: .daily,
            iconName: "figure.run",
            suggestedAnchors: ["Gym equipment", "Front door", "Yoga mat"]
        ),
        HabitTemplate(
            title: "Read",
            description: "Expand your knowledge and imagination",
            frequency: .daily,
            iconName: "book.fill",
            suggestedAnchors: ["Bookshelf", "Bedside table", "Favorite reading spot"]
        ),
        HabitTemplate(
            title: "Journal",
            description: "Reflect on your thoughts and experiences",
            frequency: .daily,
            iconName: "pencil.and.paper",
            suggestedAnchors: ["Desk", "Journal", "Bedside table"]
        ),
        HabitTemplate(
            title: "Stretch",
            description: "Improve flexibility and prevent injuries",
            frequency: .daily,
            iconName: "figure.flexibility",
            suggestedAnchors: ["Yoga mat", "Bedroom floor", "Living room"]
        ),
        HabitTemplate(
            title: "Clean Home",
            description: "Maintain a tidy and organized living space",
            frequency: .weekly,
            iconName: "house.fill",
            suggestedAnchors: ["Cleaning supplies", "Living room", "Kitchen"]
        ),
        HabitTemplate(
            title: "Call Family",
            description: "Stay connected with loved ones",
            frequency: .weekly,
            iconName: "phone.fill",
            suggestedAnchors: ["Couch", "Kitchen table", "Favorite chair"]
        ),
        HabitTemplate(
            title: "Budget Review",
            description: "Track your finances and spending habits",
            frequency: .monthly,
            iconName: "dollarsign.circle",
            suggestedAnchors: ["Desk", "Computer", "Financial documents"]
        )
    ]
}
