import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.presentationMode) private var presentationMode
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                startPoint: isAnimating ? .topLeading : .bottomTrailing,
                endPoint: isAnimating ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    isAnimating.toggle()
                }
            }
            
            // Main content
            switch viewModel.currentStep {
            case .welcome:
                welcomeView
            case .nameInput:
                nameInputView
            case .habitSelection:
                habitSelectionView
            case .arTutorial:
                arTutorialView
            case .permissions:
                permissionsView
            case .completion:
                completionView
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Subviews
    
    private var welcomeView: some View {
        OnboardingContainerView(viewModel: viewModel, showBackButton: false) {
            VStack(spacing: 40) {
                Spacer()
                
                // App icon and title
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .shadow(radius: 5)
                    
                    Text("HabitSpace")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .scaleEffect(isAnimating ? 1.02 : 1.0)
                .animation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                
                // Feature highlights
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "arkit", title: "AR Habit Anchors", description: "Place virtual reminders in your space")
                    FeatureRow(icon: "chart.bar.fill", title: "Track Progress", description: "Monitor your habit streaks and growth")
                    FeatureRow(icon: "bell.badge.fill", title: "Smart Reminders", description: "Get notified when you're near a habit location")
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                
                Spacer()
                
                Text("Transform your daily routines with the power of augmented reality.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
            }
        }
    }
    
    private var nameInputView: some View {
        OnboardingContainerView(viewModel: viewModel) {
            VStack(spacing: 40) {
                Spacer()
                
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
                    .padding(.bottom, 20)
                
                VStack(spacing: 20) {
                    Text("What should we call you?")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    TextField("Your name", text: $viewModel.userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 40)
                        .multilineTextAlignment(.center)
                        .font(.title3)
                        .disableAutocorrection(true)
                }
                
                Spacer()
            }
        }
    }
    
    private var habitSelectionView: some View {
        OnboardingContainerView(viewModel: viewModel) {
            VStack(spacing: 20) {
                Text("Select up to 5 habits to get started")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 15),
                        GridItem(.flexible(), spacing: 15)
                    ], spacing: 15) {
                        ForEach(viewModel.availableHabits) { habit in
                            HabitOptionView(
                                habit: habit,
                                isSelected: viewModel.selectedHabits.contains(where: { $0.id == habit.id })
                            ) {
                                withAnimation {
                                    viewModel.toggleHabit(habit)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                if !viewModel.selectedHabits.isEmpty {
                    Text("\(viewModel.selectedHabits.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var arTutorialView: some View {
        OnboardingContainerView(viewModel: viewModel) {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "arkit")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 20) {
                    TutorialStep(number: 1, title: "Find a Surface", description: "Point your camera at a flat surface like a table or floor")
                    
                    TutorialStep(number: 2, title: "Place Anchor", description: "Tap to place a virtual anchor for your habit")
                    
                    TutorialStep(number: 3, title: "Get Reminded", description: "Receive notifications when you're near the anchor")
                }
                .padding()
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                
                Spacer()
                
                Text("You'll be able to place AR anchors for each habit in the app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var permissionsView: some View {
        OnboardingContainerView(viewModel: viewModel) {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 15) {
                    PermissionRow(
                        icon: "camera.fill",
                        title: "Camera Access",
                        description: "Required to place and view AR anchors",
                        isGranted: .constant(false)
                    )
                    
                    PermissionRow(
                        icon: "location.fill",
                        title: "Location Access",
                        description: "For location-based habit reminders",
                        isGranted: .constant(false)
                    )
                    
                    PermissionRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        description: "To remind you about your habits",
                        isGranted: .constant(false)
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                Text("You can change these permissions anytime in Settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var completionView: some View {
        OnboardingContainerView(viewModel: viewModel, showNextButton: true, nextButtonAction: {
            viewModel.completeOnboarding()
            presentationMode.wrappedValue.dismiss()
        }) {
            VStack(spacing: 30) {
                Spacer()
                
                // Success animation
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 150, height: 150)
                        .scaleEffect(isAnimating ? 1.2 : 0.8)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(Animation.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: isAnimating)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.green)
                }
                
                VStack(spacing: 15) {
                    Text("You're All Set!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("You're ready to start building better habits with HabitSpace!")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 15) {
                    TipView(icon: "sparkles", text: "Place your first AR anchor by tapping the + button")
                    TipView(icon: "bell.badge.fill", text: "Enable notifications to never miss a habit")
                    TipView(icon: "chart.bar.fill", text: "Track your progress in the Stats tab")
                }
                .padding()
                .background(Color.white.opacity(0.2))
                .cornerRadius(15)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Preview
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
