import SwiftUI
import ARKit
import RealityKit
import UserNotifications
import CoreLocation
import Combine

/// Main onboarding view that guides users through the initial setup process
struct OnboardingView: View {
    // MARK: - Environment
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var anchorManager: AnchorManager
    @EnvironmentObject private var notificationManager: NotificationManager
    
    // MARK: - App Storage
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // MARK: - State
    @State private var currentStep = 0
    @State private var selectedHabits: [HabitTemplate] = []
    @State private var userName: String = ""
    @State private var animateBackground = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertType: PermissionType = .camera
    @State private var arPlacementCompleted = false
    @State private var showARTutorial = false
    
    // Animation states
    @State private var opacity = 0.0
    @State private var scale: CGFloat = 0.9
    @State private var offset: CGFloat = 50
    @State private var cardOffsets: [UUID: CGFloat] = [:]
    @State private var cardOpacities: [UUID: Double] = [:]
    
    // MARK: - Constants
    private let maxHabits = 5
    private let minHabits = 3
    private let totalSteps = 4
    
    // MARK: - Computed Properties
    private var habitTemplates: [HabitTemplate] {
        habitManager.getDefaultHabitTemplates()
    }
    
    private var canContinue: Bool {
        switch currentStep {
        case 0: // Welcome
            return true
        case 1: // Habit Selection
            return selectedHabits.count >= minHabits && selectedHabits.count <= maxHabits
        case 2: // Permissions
            return true
        case 3: // AR Tutorial
            return arPlacementCompleted
        default:
            return false
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Animated background
            backgroundGradient
            
            VStack(spacing: 0) {
                // Progress indicators
                progressIndicator
                    .padding(.top, 20)
                
                // Main content
                ZStack {
                    // Each step is in its own view for better organization
                    welcomeStep
                        .opacity(currentStep == 0 ? 1 : 0)
                        .zIndex(currentStep == 0 ? 1 : 0)
                    
                    habitSelectionStep
                        .opacity(currentStep == 1 ? 1 : 0)
                        .zIndex(currentStep == 1 ? 1 : 0)
                    
                    permissionsStep
                        .opacity(currentStep == 2 ? 1 : 0)
                        .zIndex(currentStep == 2 ? 1 : 0)
                    
                    arTutorialStep
                        .opacity(currentStep == 3 ? 1 : 0)
                        .zIndex(currentStep == 3 ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Navigation buttons
                navigationButtons
                    .padding(.bottom, 30)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentStep)
            
            // AR Tutorial overlay
            if showARTutorial {
                ARTutorialOverlay(isShowing: $showARTutorial, 
                                 arPlacementCompleted: $arPlacementCompleted,
                                 selectedHabit: selectedHabits.first)
                    .environmentObject(habitManager)
                    .environmentObject(anchorManager)
            }
        }
        .onAppear {
            startAnimations()
            setupHabitCards()
        }
        .alert(isPresented: $showPermissionAlert) {
            permissionAlert
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.blue.opacity(0.7),
                Color.purple.opacity(0.6)
            ]),
            startPoint: animateBackground ? .topLeading : .bottomTrailing,
            endPoint: animateBackground ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: true)) {
                animateBackground.toggle()
            }
        }
    }
    
    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .scaleEffect(step == currentStep ? 1.2 : 1.0)
                    .overlay(
                        step <= currentStep ? Circle().stroke(Color.white, lineWidth: 1) : nil
                    )
                    .animation(.spring(), value: currentStep)
            }
        }
        .padding()
        .background(
            Capsule()
                .fill(Color.black.opacity(0.2))
                .frame(height: 30)
        )
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 20) {
            // Back button (hidden on first step)
            if currentStep > 0 {
                Button(action: {
                    withAnimation {
                        currentStep -= 1
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
            }
            
            Spacer()
            
            // Next/Continue button
            Button(action: {
                handleContinueAction()
            }) {
                HStack {
                    Text(currentStep == totalSteps - 1 ? "Get Started" : "Continue")
                    Image(systemName: "chevron.right")
                }
                .padding()
                .foregroundColor(.white)
                .background(canContinue ? Color.blue : Color.gray)
                .cornerRadius(10)
                .shadow(radius: canContinue ? 5 : 0)
            }
            .disabled(!canContinue)
        }
        .padding(.horizontal, 30)
    }
    
    // MARK: - Step 1: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 30) {
            // App logo/icon
            Image(systemName: "sparkles.rectangle.stack.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .foregroundColor(.white)
                .padding()
                .background(Circle().fill(Color.blue.opacity(0.3)))
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .scaleEffect(animateBackground ? 1.1 : 1.0)
                        .opacity(animateBackground ? 0.5 : 1.0)
                )
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), 
                          value: animateBackground)
                .offset(y: offset)
                .opacity(opacity)
                .scaleEffect(scale)
            
            // App name
            Text("HabitSpace")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)
                .offset(y: offset)
                .opacity(opacity)
                .scaleEffect(scale)
            
            // Tagline
            Text("Build habits in your space")
                .font(.title2)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .offset(y: offset)
                .opacity(opacity)
                .scaleEffect(scale)
            
            // App description
            Text("HabitSpace uses augmented reality to anchor your habits to real-world locations and objects, making them easier to remember and complete.")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .offset(y: offset)
                .opacity(opacity)
                .scaleEffect(scale)
            
            // Name input (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?")
                    .font(.headline)
                    .foregroundColor(.white)
                
                TextField("Your name", text: $userName)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .accentColor(.white)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .offset(y: offset)
            .opacity(opacity)
            .scaleEffect(scale)
            
            // Visual example
            Image(systemName: "arkit")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.white.opacity(0.9))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.2))
                )
                .offset(y: offset)
                .opacity(opacity)
                .scaleEffect(scale)
        }
        .padding()
    }
    
    // MARK: - Step 2: Habit Selection
    private var habitSelectionStep: some View {
        VStack(spacing: 20) {
            // Header
            Text("Select 3-5 Habits")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top)
            
            // Subheader
            Text("Choose habits you want to build")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 5)
            
            // Selected count
            Text("\(selectedHabits.count)/\(maxHabits) selected")
                .font(.caption)
                .foregroundColor(selectedHabits.count >= minHabits ? .white : .yellow)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.2))
                )
            
            // Habit templates list
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 15) {
                    ForEach(habitTemplates) { template in
                        HabitTemplateCard(
                            template: template,
                            isSelected: selectedHabits.contains { $0.id == template.id },
                            onToggle: { toggleHabitSelection(template) }
                        )
                        .offset(x: cardOffsets[template.id, default: 0])
                        .opacity(cardOpacities[template.id, default: 1.0])
                    }
                }
                .padding(.horizontal)
            }
            
            // Helper text
            if selectedHabits.count < minHabits {
                Text("Please select at least \(minHabits) habits")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(.top, 5)
            } else if selectedHabits.count > maxHabits {
                Text("Please select at most \(maxHabits) habits")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(.top, 5)
            }
        }
    }
    
    // MARK: - Step 3: Permissions
    private var permissionsStep: some View {
        VStack(spacing: 30) {
            // Header
            Text("Required Permissions")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Subheader
            Text("HabitSpace needs a few permissions to work properly")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Permissions list
            VStack(spacing: 25) {
                // Camera permission
                PermissionCard(
                    icon: "camera.fill",
                    title: "Camera Access",
                    description: "Required for AR features to place habit anchors in your space",
                    buttonTitle: "Allow Camera",
                    action: { requestCameraPermission() }
                )
                
                // Notifications permission
                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Get reminded when you're near your habit anchors",
                    buttonTitle: "Allow Notifications",
                    action: { requestNotificationPermission() }
                )
                
                // Location permission
                PermissionCard(
                    icon: "location.fill",
                    title: "Location Access",
                    description: "For better AR tracking and proximity detection",
                    buttonTitle: "Allow Location",
                    action: { requestLocationPermission() }
                )
            }
            .padding(.horizontal)
            
            // Helper text
            Text("You can change these permissions later in Settings")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 10)
        }
    }
    
    // MARK: - Step 4: AR Tutorial
    private var arTutorialStep: some View {
        VStack(spacing: 25) {
            // Header
            Text("Place Your First Anchor")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Subheader
            Text("Let's place your first habit anchor in AR")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            // Tutorial image/illustration
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 300)
                
                VStack(spacing: 15) {
                    Image(systemName: "arkit")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white)
                    
                    Text("AR Tutorial")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("1. Point camera at a surface\n2. Tap to place habit anchor\n3. Confirm placement")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            
            // Start AR tutorial button
            Button(action: {
                showARTutorial = true
            }) {
                Text("Start AR Tutorial")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.blue)
                    )
                    .padding(.horizontal)
            }
            
            // Skip option for devices without AR
            if !ARWorldTrackingConfiguration.isSupported {
                Button(action: {
                    arPlacementCompleted = true
                }) {
                    Text("Skip (AR not supported on this device)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 5)
                }
            }
        }
    }
    
    // MARK: - Permission Alert
    private var permissionAlert: Alert {
        switch permissionAlertType {
        case .camera:
            return Alert(
                title: Text("Camera Permission Required"),
                message: Text("HabitSpace needs camera access for AR features. Please enable it in Settings."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        case .notifications:
            return Alert(
                title: Text("Notification Permission Required"),
                message: Text("HabitSpace needs notification permission to remind you about habits. Please enable it in Settings."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        case .location:
            return Alert(
                title: Text("Location Permission Recommended"),
                message: Text("HabitSpace works best with location data for AR tracking. Please enable it in Settings."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - Actions
    
    private func startAnimations() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) {
            opacity = 1.0
            scale = 1.0
            offset = 0
        }
    }
    
    private func setupHabitCards() {
        // Reset card positions for staggered animation
        for (index, template) in habitTemplates.enumerated() {
            cardOffsets[template.id] = 50
            cardOpacities[template.id] = 0.0
            
            // Animate cards with staggered delay
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.1)) {
                cardOffsets[template.id] = 0
                cardOpacities[template.id] = 1.0
            }
        }
    }
    
    private func toggleHabitSelection(_ template: HabitTemplate) {
        if let index = selectedHabits.firstIndex(where: { $0.id == template.id }) {
            selectedHabits.remove(at: index)
        } else {
            // Only add if we haven't reached max
            if selectedHabits.count < maxHabits {
                selectedHabits.append(template)
            }
        }
    }
    
    private func handleContinueAction() {
        switch currentStep {
        case 0: // Welcome -> Habit Selection
            withAnimation {
                currentStep += 1
            }
            
        case 1: // Habit Selection -> Permissions
            withAnimation {
                currentStep += 1
            }
            
        case 2: // Permissions -> AR Tutorial
            withAnimation {
                currentStep += 1
            }
            
        case 3: // AR Tutorial -> Complete Onboarding
            completeOnboarding()
            
        default:
            break
        }
    }
    
    private func completeOnboarding() {
        // Save user name if provided
        if !userName.isEmpty {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
        
        // Create selected habits
        habitManager.createDefaultHabits(from: selectedHabits)
        
        // Mark onboarding as completed
        hasCompletedOnboarding = true
        habitManager.isFirstLaunch = false
        
        // Schedule notifications for habits
        notificationManager.scheduleAllNotifications()
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    permissionAlertType = .camera
                    showPermissionAlert = true
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if !granted {
                    permissionAlertType = .notifications
                    showPermissionAlert = true
                }
            }
        }
    }
    
    private func requestLocationPermission() {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        
        // Check authorization status after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if CLLocationManager.authorizationStatus() == .denied {
                permissionAlertType = .location
                showPermissionAlert = true
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Supporting Views

/// Card for displaying habit templates
struct HabitTemplateCard: View {
    let template: HabitTemplate
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 15) {
                // Icon
                Image(systemName: template.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundColor(isSelected ? template.color : .white.opacity(0.7))
                    .padding(10)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.white : Color.white.opacity(0.2))
                    )
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                    
                    Text(template.frequency.displayName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? template.color : .white.opacity(0.5))
                    .font(.title2)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(isSelected ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? template.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

/// Card for permission requests
struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 15) {
                // Icon
                Image(systemName: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                    )
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Permission button
            Button(action: action) {
                Text(buttonTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.3))
        )
    }
}

/// AR Tutorial Overlay
struct ARTutorialOverlay: View {
    @Binding var isShowing: Bool
    @Binding var arPlacementCompleted: Bool
    var selectedHabit: HabitTemplate?
    
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var anchorManager: AnchorManager
    
    @State private var tutorialStep = 0
    @State private var showPlacementSuccess = false
    @State private var placedAnchorId: UUID?
    
    var body: some View {
        ZStack {
            // AR View background (would be a real AR view in production)
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    if tutorialStep == 1 {
                        // Simulate tap to place anchor
                        placeAnchor()
                    }
                }
            
            // Mock AR content
            VStack {
                // Mock camera view
                ZStack {
                    // Simulated AR view
                    Image(systemName: "camera.viewfinder")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Simulated plane detection
                    if tutorialStep == 0 {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: 250, height: 150)
                            .opacity(0.7)
                    }
                    
                    // Simulated anchor placement
                    if tutorialStep >= 1 {
                        Circle()
                            .fill(selectedHabit?.color ?? Color.blue)
                            .frame(width: 30, height: 30)
                            .blur(radius: 10)
                            .opacity(0.8)
                    }
                    
                    // Success animation
                    if showPlacementSuccess {
                        SuccessAnimation()
                            .frame(width: 200, height: 200)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 400)
                .background(Color.black)
                .cornerRadius(20)
                .padding()
                
                // Tutorial instructions
                VStack(spacing: 20) {
                    Text(tutorialStepTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(tutorialStepInstructions)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Action button
                    Button(action: {
                        handleTutorialAction()
                    }) {
                        Text(tutorialButtonTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.blue)
                            )
                            .padding(.horizontal)
                    }
                    .padding(.top, 10)
                }
                .padding()
                
                // Exit button
                Button(action: {
                    isShowing = false
                }) {
                    Text("Exit Tutorial")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 20)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: tutorialStep)
        .animation(.easeInOut, value: showPlacementSuccess)
        .onAppear {
            // Ensure AR session is started
            anchorManager.startARSession()
        }
    }
    
    // Tutorial content based on current step
    private var tutorialStepTitle: String {
        switch tutorialStep {
        case 0:
            return "Find a Surface"
        case 1:
            return "Tap to Place Anchor"
        case 2:
            return "Anchor Placed!"
        default:
            return ""
        }
    }
    
    private var tutorialStepInstructions: String {
        switch tutorialStep {
        case 0:
            return "Move your phone around to detect horizontal surfaces. Yellow rectangles will appear on detected surfaces."
        case 1:
            return "Tap on the detected surface to place your habit anchor. This is where you'll be reminded about your habit."
        case 2:
            return "Great job! You've placed your first habit anchor. When you're near this location, you'll receive a reminder about your habit."
        default:
            return ""
        }
    }
    
    private var tutorialButtonTitle: String {
        switch tutorialStep {
        case 0:
            return "Surface Detected"
        case 1:
            return "Place Anchor Here"
        case 2:
            return "Complete Tutorial"
        default:
            return ""
        }
    }
    
    // Handle button taps for each tutorial step
    private func handleTutorialAction() {
        switch tutorialStep {
        case 0:
            // Move to placement step
            tutorialStep = 1
            
        case 1:
            // Simulate anchor placement
            placeAnchor()
            
        case 2:
            // Close tutorial
            isShowing = false
            
        default:
            break
        }
    }
    
    // Place an anchor for the selected habit
    private func placeAnchor() {
        tutorialStep = 2
        showPlacementSuccess = true
        
        // Create a mock anchor for the first habit
        if let habitId = selectedHabit?.id {
            // In a real implementation, we'd use the actual transform from ARKit
            // Here we're just creating a mock anchor
            let mockTransform = simd_float4x4(
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(0, 0, -0.5, 1)
            )
            
            // Place anchor
            if let anchorViewModel = anchorManager.placeAnchor(
                habitId: habitId,
                worldTransform: mockTransform,
                iconType: .glow
            ) {
                placedAnchorId = anchorViewModel.id
            }
        }
        
        // Mark as completed after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            arPlacementCompleted = true
        }
    }
}

// A success animation for anchor placement
struct SuccessAnimation: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = 0.0
    
    var body: some View {
        ZStack {
            // Expanding circles
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .scaleEffect(scale * (CGFloat(index) * 0.2 + 1.0))
                    .opacity(opacity * (1.0 - Double(index) * 0.2))
            }
            
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.green)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
                rotation = 360
            }
        }
    }
}

// Permission type enum
enum PermissionType {
    case camera
    case notifications
    case location
}
