import SwiftUI
import Combine

/// Main tab view that serves as the primary navigation interface for the app
struct MainTabView: View {
    // MARK: - Environment
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var anchorManager: AnchorManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var aiManager: AIManager
    
    // MARK: - State
    @State private var selectedTab: TabItem = .today
    @State private var previousTab: TabItem = .today
    @State private var tabBarVisible: Bool = true
    @State private var tabBadgeCounts: [TabItem: Int] = [:]
    @State private var tabAnimation: Namespace.ID = Namespace().wrappedValue
    
    // For deep linking
    @State private var deepLinkDestination: DeepLinkDestination?
    @State private var deepLinkData: Any?
    
    // For tab animations
    @State private var tabBarOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    
    // MARK: - Notification Observers
    @State private var notificationObservers: Set<AnyCancellable> = []
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Tab content
                tabContent
                    .onChange(of: selectedTab) { newTab in
                        handleTabChange(from: previousTab, to: newTab)
                        previousTab = newTab
                    }
                
                // Custom tab bar
                if tabBarVisible {
                    customTabBar
                        .transition(.move(edge: .bottom))
                        .animation(.spring(), value: tabBarVisible)
                        .offset(y: tabBarOffset)
                }
            }
            .onAppear {
                setupTabBadges()
                setupNotificationObservers()
                checkForDeepLinks()
            }
            .onDisappear {
                // Clean up observers
                notificationObservers.forEach { $0.cancel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshData()
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Tab Content
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .today:
                HabitTrackerView()
                    .environmentObject(habitManager)
                    .environmentObject(notificationManager)
                    .environmentObject(aiManager)
                    .tabScrollObserver { offset in
                        handleScroll(offset: offset)
                    }
                
            case .ar:
                ARPlacementView()
                    .environmentObject(habitManager)
                    .environmentObject(anchorManager)
                    .environmentObject(notificationManager)
                
            case .insights:
                InsightsView()
                    .environmentObject(habitManager)
                    .environmentObject(aiManager)
                    .tabScrollObserver { offset in
                        handleScroll(offset: offset)
                    }
                
            case .settings:
                SettingsView()
                    .environmentObject(habitManager)
                    .environmentObject(anchorManager)
                    .environmentObject(notificationManager)
                    .environmentObject(aiManager)
                    .tabScrollObserver { offset in
                        handleScroll(offset: offset)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Custom Tab Bar
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
    
    private func tabButton(_ tab: TabItem) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                // If tapping the same tab, perform tab-specific action
                if selectedTab == tab {
                    performTabAction(tab)
                } else {
                    selectedTab = tab
                }
            }
        }) {
            VStack(spacing: 4) {
                ZStack {
                    // Tab icon
                    Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 22, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? tab.color : .gray)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(selectedTab == tab ? tab.color.opacity(0.2) : Color.clear)
                                .matchedGeometryEffect(id: selectedTab == tab ? "tabBackground" : "none\(tab.rawValue)", in: tabAnimation)
                        )
                        .overlay(
                            // Badge
                            badgeView(for: tab)
                                .offset(x: 16, y: -16)
                        )
                }
                
                // Tab label
                Text(tab.title)
                    .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
                    .foregroundColor(selectedTab == tab ? tab.color : .gray)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TabButtonStyle())
    }
    
    private func badgeView(for tab: TabItem) -> some View {
        Group {
            if let count = tabBadgeCounts[tab], count > 0 {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 18, height: 18)
                    
                    if count < 10 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("9+")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - Methods
    
    /// Set up initial badge counts for tabs
    private func setupTabBadges() {
        updateTodayTabBadge()
        updateInsightsTabBadge()
    }
    
    /// Update the badge count for the Today tab
    private func updateTodayTabBadge() {
        let uncompletedCount = habitManager.todaysHabits.filter { 
            !$0.isCompletedToday && !$0.isSkippedToday 
        }.count
        
        withAnimation {
            tabBadgeCounts[.today] = uncompletedCount
        }
    }
    
    /// Update the badge count for the Insights tab
    private func updateInsightsTabBadge() {
        let newSuggestionsCount = aiManager.suggestions.filter { !$0.isAccepted }.count
        
        withAnimation {
            tabBadgeCounts[.insights] = newSuggestionsCount
        }
    }
    
    /// Handle tab change events
    private func handleTabChange(from oldTab: TabItem, to newTab: TabItem) {
        // Reset scroll behavior
        tabBarVisible = true
        tabBarOffset = 0
        
        // Clear badge when navigating to tab
        if tabBadgeCounts[newTab] != nil {
            withAnimation {
                tabBadgeCounts[newTab] = 0
            }
        }
        
        // Tab-specific actions
        switch newTab {
        case .ar:
            // Start AR session when navigating to AR tab
            anchorManager.startARSession()
        case .today:
            // Refresh habits when navigating to Today tab
            habitManager.loadHabits()
        case .insights:
            // Refresh analytics when navigating to Insights tab
            habitManager.calculateStatistics()
            aiManager.generateSuggestions(for: habitManager)
        case .settings:
            break
        }
    }
    
    /// Perform action when tapping the current tab again
    private func performTabAction(_ tab: TabItem) {
        switch tab {
        case .today:
            // Scroll to top or show uncompleted habits
            NotificationCenter.default.post(name: .scrollToTop, object: nil)
        case .ar:
            // Reset AR session
            anchorManager.resetARSession()
        case .insights:
            // Refresh analytics data
            habitManager.calculateStatistics()
            aiManager.generateSuggestions(for: habitManager)
        case .settings:
            // Nothing special for settings
            break
        }
    }
    
    /// Handle scroll events to show/hide tab bar
    private func handleScroll(offset: CGFloat) {
        // Calculate delta from last position
        let delta = offset - lastScrollOffset
        lastScrollOffset = offset
        
        // Only respond to significant changes to avoid jitter
        guard abs(delta) > 5 else { return }
        
        // Update tab bar visibility with animation
        withAnimation(.easeOut(duration: 0.2)) {
            if delta > 0 {
                // Scrolling down, hide tab bar
                tabBarOffset = min(tabBarOffset + delta, 100)
                if tabBarOffset > 80 {
                    tabBarVisible = false
                }
            } else {
                // Scrolling up, show tab bar
                tabBarOffset = max(tabBarOffset + delta, 0)
                tabBarVisible = true
            }
        }
    }
    
    /// Set up notification observers
    private func setupNotificationObservers() {
        // Listen for habit data changes
        NotificationCenter.default.publisher(for: .habitDataChanged)
            .sink { [weak self] _ in
                self?.updateTodayTabBadge()
            }
            .store(in: &notificationObservers)
        
        // Listen for suggestion changes
        NotificationCenter.default.publisher(for: .openHabitDetail)
            .sink { [weak self] notification in
                if let habitId = notification.userInfo?["habitId"] as? UUID {
                    self?.selectedTab = .today
                    // Pass the habit ID to the habit detail view
                    // This would typically use a coordinator pattern or state object
                    NotificationCenter.default.post(
                        name: .openHabitDetail,
                        object: nil,
                        userInfo: ["habitId": habitId]
                    )
                }
            }
            .store(in: &notificationObservers)
        
        // Listen for focus on anchor requests
        NotificationCenter.default.publisher(for: .focusOnAnchor)
            .sink { [weak self] notification in
                if let anchorId = notification.userInfo?["anchorId"] as? UUID {
                    self?.selectedTab = .ar
                    // Focus on the anchor in the AR view
                    self?.anchorManager.focusOnAnchor(anchorId: anchorId)
                }
            }
            .store(in: &notificationObservers)
    }
    
    /// Check for deep links when app launches or becomes active
    private func checkForDeepLinks() {
        // This would typically use the SceneDelegate or App's onOpenURL
        // For this MVP, we're just simulating deep link handling
        
        // Example: Handle a deep link from a notification
        if let deepLink = deepLinkDestination {
            handleDeepLink(deepLink)
        }
    }
    
    /// Handle incoming deep links
    private func handleDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .habit(let habitId):
            selectedTab = .today
            // Pass the habit ID to the habit detail view
            NotificationCenter.default.post(
                name: .openHabitDetail,
                object: nil,
                userInfo: ["habitId": habitId]
            )
            
        case .anchor(let anchorId):
            selectedTab = .ar
            // Focus on the anchor in the AR view
            anchorManager.focusOnAnchor(anchorId: anchorId)
            
        case .suggestion(let suggestionId):
            selectedTab = .insights
            // Open the suggestion in the insights view
            NotificationCenter.default.post(
                name: .openSuggestion,
                object: nil,
                userInfo: ["suggestionId": suggestionId]
            )
        }
    }
    
    /// Refresh data when app becomes active
    private func refreshData() {
        habitManager.loadHabits()
        updateTodayTabBadge()
        updateInsightsTabBadge()
    }
}

// MARK: - Tab Items
enum TabItem: String, CaseIterable, Identifiable {
    case today
    case ar
    case insights
    case settings
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .today: return "Today"
        case .ar: return "AR"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .today: return "list.bullet"
        case .ar: return "arkit"
        case .insights: return "chart.bar"
        case .settings: return "gear"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .today: return "list.bullet.fill"
        case .ar: return "arkit"
        case .insights: return "chart.bar.fill"
        case .settings: return "gear.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .today: return .blue
        case .ar: return .purple
        case .insights: return .orange
        case .settings: return .gray
        }
    }
}

// MARK: - Custom Button Style
struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Tab Scroll Observer
struct TabScrollObserverModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .global).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                onScroll(value)
            }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func tabScrollObserver(onScroll: @escaping (CGFloat) -> Void) -> some View {
        self.modifier(TabScrollObserverModifier(onScroll: onScroll))
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let scrollToTop = Notification.Name("scrollToTop")
    static let openHabitDetail = Notification.Name("openHabitDetail")
    static let openSuggestion = Notification.Name("openSuggestion")
}

// MARK: - Placeholder Views
// These would be replaced by actual view implementations

struct ARPlacementView: View {
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var anchorManager: AnchorManager
    
    var body: some View {
        VStack {
            Text("AR Placement View")
                .font(.title)
                .padding()
            
            if anchorManager.isARAvailable {
                ARViewContainer()
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("AR is not available on this device")
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject private var anchorManager: AnchorManager
    
    func makeUIView(context: Context) -> UIView {
        #if !targetEnvironment(simulator)
        let arView = ARView(frame: .zero)
        anchorManager.setupARView(arView)
        return arView
        #else
        // Return a placeholder view for simulator
        let view = UIView()
        view.backgroundColor = .black
        let label = UILabel()
        label.text = "AR View (Simulator)"
        label.textColor = .white
        label.textAlignment = .center
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
        #endif
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Updates happen through the AnchorManager
    }
}

struct InsightsView: View {
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var aiManager: AIManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Insights & Analytics")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Placeholder for insights content
                Text("Your habit insights and analytics will appear here")
                    .foregroundColor(.secondary)
                    .padding()
            }
            .padding()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var habitManager: HabitManager
    @EnvironmentObject private var notificationManager: NotificationManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Placeholder for settings content
                Text("App settings and preferences will appear here")
                    .foregroundColor(.secondary)
                    .padding()
            }
            .padding()
        }
    }
}
