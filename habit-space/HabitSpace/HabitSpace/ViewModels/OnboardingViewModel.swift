import Foundation
import SwiftUI

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedHabits: [HabitOption] = []
    @Published var userName: String = ""
    
    let availableHabits: [HabitOption] = [
        HabitOption(id: 1, name: "Drink Water", icon: "drop.fill", description: "Stay hydrated throughout the day"),
        HabitOption(id: 2, name: "Meditate", icon: "leaf.fill", description: "Practice mindfulness daily"),
        HabitOption(id: 3, name: "Exercise", icon: "figure.walk", description: "Get moving for better health"),
        HabitOption(id: 4, name: "Read", icon: "book.fill", description: "Expand your knowledge"),
        HabitOption(id: 5, name: "Sleep Well", icon: "moon.zzz.fill", description: "Prioritize quality rest"),
        HabitOption(id: 6, name: "Journal", icon: "note.text", description: "Reflect on your day"),
        HabitOption(id: 7, name: "Stretch", icon: "figure.cooldown", description: "Keep your body flexible"),
        HabitOption(id: 8, name: "Gratitude", icon: "heart.fill", description: "Practice daily gratitude")
    ]
    
    // Move to the next onboarding step
    func next() {
        withAnimation {
            currentStep = currentStep.next()
        }
    }
    
    // Move to the previous onboarding step
    func previous() {
        withAnimation {
            currentStep = currentStep.previous()
        }
    }
    
    // Toggle habit selection
    func toggleHabit(_ habit: HabitOption) {
        if let index = selectedHabits.firstIndex(where: { $0.id == habit.id }) {
            selectedHabits.remove(at: index)
        } else if selectedHabits.count < 5 {
            selectedHabits.append(habit)
        }
    }
    
    // Save the onboarding data and complete the process
    func completeOnboarding() {
        // Save selected habits to Core Data
        let coreDataManager = CoreDataManager.shared
        for habitOption in selectedHabits {
            _ = coreDataManager.createHabit(
                name: habitOption.name,
                iconName: habitOption.icon,
                targetCount: 1
            )
        }
        
        // Mark onboarding as completed in UserDefaults
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        // Save the user's name if provided
        if !userName.isEmpty {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
    }
}

// MARK: - Data Models
struct HabitOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let icon: String
    let description: String
}

// MARK: - Onboarding Steps
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case nameInput
    case habitSelection
    case arTutorial
    case permissions
    case completion
    
    var title: String {
        switch self {
        case .welcome: return "Welcome to HabitSpace"
        case .nameInput: return "What's your name?"
        case .habitSelection: return "Choose Your Habits"
        case .arTutorial: return "AR Habit Anchors"
        case .permissions: return "Enable Permissions"
        case .completion: return "You're All Set!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "Transform your daily routines with the power of augmented reality."
        case .nameInput: return "We'll use this to personalize your experience."
        case .habitSelection: return "Select up to 5 habits you'd like to focus on. You can always add more later."
        case .arTutorial: return "Place virtual anchors in your space to remind you of your habits when you're nearby."
        case .permissions: return "We need a few permissions to make HabitSpace work its magic."
        case .completion: return "You're ready to start building better habits with HabitSpace!"
        }
    }
    
    var progress: Double {
        Double(rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    func next() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? self
    }
    
    func previous() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? self
    }
}
