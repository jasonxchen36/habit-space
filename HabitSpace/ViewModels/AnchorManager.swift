import SwiftUI
import ARKit
import RealityKit
import CoreData
import Combine
import CoreLocation

#if os(visionOS)
import RealityKitContent
#endif

/// Manages AR anchors and sessions for the HabitSpace app
class AnchorManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    /// Current AR session state
    @Published var sessionState: ARSessionState = .initializing
    
    /// List of anchor view models
    @Published var anchors: [AnchorViewModel] = []
    
    /// Currently active anchor (in proximity)
    @Published var activeAnchor: AnchorViewModel?
    
    /// Error message if AR session fails
    @Published var sessionErrorMessage: String?
    
    /// Whether AR features are available on this device
    @Published var isARAvailable: Bool = ARWorldTrackingConfiguration.isSupported
    
    /// Whether the AR camera is currently active
    @Published var isCameraActive: Bool = false
    
    /// Whether plane detection is in progress
    @Published var isDetectingPlanes: Bool = false
    
    /// Detected AR planes
    @Published var detectedPlanes: [ARPlaneAnchor] = []
    
    /// Whether world mapping is in progress
    @Published var isMappingWorld: Bool = false
    
    /// Whether an anchor is being placed
    @Published var isPlacingAnchor: Bool = false
    
    // MARK: - Private Properties
    
    /// The AR session
    private var arSession: ARSession?
    
    /// AR configuration
    private var configuration: ARWorldTrackingConfiguration?
    
    /// AR scene view (iOS)
    #if !os(visionOS)
    private var arView: ARView?
    #endif
    
    /// Core Data context
    private var viewContext: NSManagedObjectContext?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Location manager for geofencing fallback
    private let locationManager = CLLocationManager()
    
    /// Timer for proximity checks
    private var proximityTimer: Timer?
    
    /// Current world map for persistence
    private var currentWorldMap: ARWorldMap?
    
    /// Anchor entity cache for quick access
    private var anchorEntities: [UUID: AnchorEntity] = [:]
    
    /// Visual entities for anchors
    private var visualEntities: [UUID: ModelEntity] = [:]
    
    /// Asset cache for 3D models
    private var assetCache: [String: Entity] = [:]
    
    /// Habit manager reference for notifications
    private weak var habitManager: HabitManager?
    
    /// Notification manager reference
    private weak var notificationManager: NotificationManager?
    
    // MARK: - Initialization
    
    /// Initialize the AnchorManager with Core Data context
    /// - Parameter context: The NSManagedObjectContext to use for database operations
    func initialize(context: NSManagedObjectContext) {
        self.viewContext = context
        
        // Set up location manager for geofencing fallback
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        // Register value transformer for simd_float4x4
        WorldTransformValueTransformer.register()
        
        // Load anchors from Core Data
        loadAnchors()
        
        // Check AR availability
        checkARAvailability()
    }
    
    /// Set the habit manager reference
    /// - Parameter habitManager: The habit manager instance
    func setHabitManager(_ habitManager: HabitManager) {
        self.habitManager = habitManager
    }
    
    /// Set the notification manager reference
    /// - Parameter notificationManager: The notification manager instance
    func setNotificationManager(_ notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }
    
    // MARK: - AR Session Management
    
    /// Start the AR session
    func startARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            sessionErrorMessage = "AR is not supported on this device"
            sessionState = .failed
            return
        }
        
        // Create AR session if needed
        if arSession == nil {
            arSession = ARSession()
            arSession?.delegate = self
        }
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        #if !os(visionOS)
        // iOS-specific configuration
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        #endif
        
        // Start session
        arSession?.run(config, options: [.resetTracking, .removeExistingAnchors])
        configuration = config
        sessionState = .running
        isCameraActive = true
        isDetectingPlanes = true
        
        // Start proximity detection
        startProximityDetection()
    }
    
    /// Pause the AR session
    func pauseARSession() {
        arSession?.pause()
        isCameraActive = false
        sessionState = .paused
        stopProximityDetection()
    }
    
    /// Resume the AR session
    func resumeARSession() {
        guard let configuration = configuration else {
            startARSession()
            return
        }
        
        arSession?.run(configuration)
        isCameraActive = true
        sessionState = .running
        startProximityDetection()
    }
    
    /// Reset the AR session
    func resetARSession() {
        guard let configuration = configuration else {
            startARSession()
            return
        }
        
        arSession?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        sessionState = .running
        isCameraActive = true
    }
    
    // MARK: - AR View Setup
    
    #if !os(visionOS)
    /// Set up the AR view for iOS
    /// - Parameter arView: The ARView to use
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        // Configure AR view
        arView.session = arSession ?? ARSession()
        
        if self.arSession == nil {
            self.arSession = arView.session
            self.arSession?.delegate = self
        }
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        // Load existing anchors into the scene
        loadAnchorEntities()
    }
    #endif
    
    #if os(visionOS)
    /// Set up the RealityKit content for visionOS
    /// - Parameter content: The RealityKit content
    func setupRealityContent(_ content: inout RealityKitContent) {
        // Configure for visionOS
        // Load existing anchors into the scene
        loadAnchorEntities()
    }
    #endif
    
    // MARK: - Anchor Placement
    
    /// Begin anchor placement mode
    /// - Parameter habitId: The ID of the habit to associate with the anchor
    func beginAnchorPlacement(for habitId: UUID) {
        isPlacingAnchor = true
        
        // Ensure AR session is running
        if sessionState != .running {
            startARSession()
        }
        
        // Enable plane detection if not already enabled
        if let config = configuration, !config.planeDetection.contains(.horizontal) {
            config.planeDetection = [.horizontal, .vertical]
            arSession?.run(config)
        }
        
        isDetectingPlanes = true
    }
    
    /// Cancel anchor placement mode
    func cancelAnchorPlacement() {
        isPlacingAnchor = false
    }
    
    /// Place an anchor at the specified position
    /// - Parameters:
    ///   - habitId: The ID of the habit to associate with the anchor
    ///   - worldTransform: The world transform for the anchor
    ///   - iconType: The type of icon to display
    /// - Returns: The created anchor view model
    @discardableResult
    func placeAnchor(habitId: UUID, worldTransform: simd_float4x4, iconType: AnchorIconType) -> AnchorViewModel? {
        guard let context = viewContext else { return nil }
        
        // Create Core Data anchor
        let newAnchor = Anchor(context: context)
        newAnchor.id = UUID()
        newAnchor.habitID = habitId
        newAnchor.iconType = iconType.rawValue
        newAnchor.createdAt = Date()
        newAnchor.isActive = true
        
        // Save world transform as binary data
        let transformData = try? NSKeyedArchiver.archivedData(withRootObject: worldTransform, requiringSecureCoding: true)
        newAnchor.worldTransform = transformData
        
        // Associate with habit
        if let habit = habitManager?.fetchHabitObject(withId: habitId) {
            newAnchor.habit = habit
        }
        
        do {
            try context.save()
            
            // Create view model
            let viewModel = AnchorViewModel(anchor: newAnchor, transform: worldTransform)
            anchors.append(viewModel)
            
            // Create AR anchor entity
            createAnchorEntity(for: viewModel)
            
            // Save world map for persistence
            saveWorldMap()
            
            // Notify that anchor data has changed
            NotificationCenter.default.post(name: .anchorDataChanged, object: nil)
            
            isPlacingAnchor = false
            return viewModel
        } catch {
            print("Failed to save anchor: \(error)")
            return nil
        }
    }
    
    /// Handle tap gesture for anchor placement
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        #if !os(visionOS)
        guard isPlacingAnchor,
              let arView = arView,
              let habitId = habitManager?.habits.first?.id else { return }
        
        // Get tap location
        let tapLocation = gesture.location(in: arView)
        
        // Perform hit test
        let results = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
        
        if let firstResult = results.first {
            // Place anchor at hit test result
            let iconType = AnchorIconType.glow // Default icon type
            placeAnchor(habitId: habitId, worldTransform: firstResult.worldTransform, iconType: iconType)
        }
        #endif
    }
    
    /// Create an AR anchor entity for a view model
    /// - Parameter viewModel: The anchor view model
    private func createAnchorEntity(for viewModel: AnchorViewModel) {
        #if !os(visionOS)
        guard let arView = arView else { return }
        
        // Create anchor entity
        let anchorEntity = AnchorEntity(world: viewModel.worldTransform)
        
        // Create visual entity based on icon type
        let visualEntity = createVisualEntity(for: viewModel.iconType)
        anchorEntity.addChild(visualEntity)
        
        // Add to scene
        arView.scene.addAnchor(anchorEntity)
        
        // Cache entities
        anchorEntities[viewModel.id] = anchorEntity
        visualEntities[viewModel.id] = visualEntity
        #endif
    }
    
    /// Create a visual entity for an anchor
    /// - Parameter iconType: The type of icon to display
    /// - Returns: The created model entity
    private func createVisualEntity(for iconType: AnchorIconType) -> ModelEntity {
        // Create different visuals based on icon type
        switch iconType {
        case .glow:
            return createGlowEntity()
        case .emoji:
            return createEmojiEntity()
        case .model3D:
            return create3DModelEntity()
        }
    }
    
    /// Create a glowing sphere entity
    /// - Returns: The created model entity
    private func createGlowEntity() -> ModelEntity {
        // Create a simple sphere with emissive material
        let sphere = MeshResource.generateSphere(radius: 0.05)
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let entity = ModelEntity(mesh: sphere, materials: [material])
        
        // Add point light for glow effect
        let light = PointLight()
        light.color = .blue
        light.intensity = 1000
        light.attenuationRadius = 0.5
        
        let lightEntity = Entity()
        lightEntity.components[PointLightComponent.self] = light
        entity.addChild(lightEntity)
        
        return entity
    }
    
    /// Create an emoji text entity
    /// - Returns: The created model entity
    private func createEmojiEntity() -> ModelEntity {
        // Create a text mesh with emoji
        let mesh = MeshResource.generateText("✅", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1), containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        
        let material = SimpleMaterial(color: .white, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }
    
    /// Create a 3D model entity
    /// - Returns: The created model entity
    private func create3DModelEntity() -> ModelEntity {
        // Check cache first
        if let cachedEntity = assetCache["habitIcon"] as? ModelEntity {
            return cachedEntity.clone(recursive: true)
        }
        
        // Create a simple box as fallback
        let box = MeshResource.generateBox(size: 0.05)
        let material = SimpleMaterial(color: .green, isMetallic: true)
        let entity = ModelEntity(mesh: box, materials: [material])
        
        // In a real app, we would load a USDZ model here
        // ModelEntity.loadModelAsync(named: "HabitIcon.usdz")
        
        // Cache for reuse
        assetCache["habitIcon"] = entity
        
        return entity.clone(recursive: true)
    }
    
    // MARK: - Anchor Persistence
    
    /// Load anchors from Core Data
    func loadAnchors() {
        guard let context = viewContext else { return }
        
        let request: NSFetchRequest<Anchor> = Anchor.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        
        do {
            let fetchedAnchors = try context.fetch(request)
            
            // Convert to view models
            anchors = fetchedAnchors.compactMap { anchor in
                guard let transformData = anchor.worldTransform,
                      let transform = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSObject.self, from: transformData) as? simd_float4x4 else {
                    return nil
                }
                
                return AnchorViewModel(anchor: anchor, transform: transform)
            }
            
            // Load into AR scene if session is running
            if sessionState == .running {
                loadAnchorEntities()
            }
            
        } catch {
            print("Failed to fetch anchors: \(error)")
        }
    }
    
    /// Load anchor entities into the AR scene
    private func loadAnchorEntities() {
        #if !os(visionOS)
        guard let arView = arView else { return }
        
        // Clear existing anchors
        for (_, entity) in anchorEntities {
            arView.scene.removeAnchor(entity)
        }
        
        anchorEntities.removeAll()
        visualEntities.removeAll()
        
        // Add each anchor to the scene
        for anchor in anchors {
            let anchorEntity = AnchorEntity(world: anchor.worldTransform)
            let visualEntity = createVisualEntity(for: anchor.iconType)
            anchorEntity.addChild(visualEntity)
            
            arView.scene.addAnchor(anchorEntity)
            
            anchorEntities[anchor.id] = anchorEntity
            visualEntities[anchor.id] = visualEntity
        }
        #endif
    }
    
    /// Save the current AR world map
    private func saveWorldMap() {
        #if !os(visionOS)
        guard ARWorldTrackingConfiguration.supportsWorldMap else { return }
        
        arSession?.getCurrentWorldMap { worldMap, error in
            guard let worldMap = worldMap, error == nil else {
                print("Failed to get world map: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            self.currentWorldMap = worldMap
            
            // Save world map to user defaults
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                UserDefaults.standard.set(data, forKey: "ARWorldMap")
            } catch {
                print("Failed to save world map: \(error)")
            }
        }
        #endif
    }
    
    /// Load a saved AR world map
    private func loadWorldMap() -> ARWorldMap? {
        #if !os(visionOS)
        guard ARWorldTrackingConfiguration.supportsWorldMap,
              let data = UserDefaults.standard.data(forKey: "ARWorldMap") else {
            return nil
        }
        
        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                return nil
            }
            return worldMap
        } catch {
            print("Failed to load world map: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
    
    /// Restore a saved AR session with world map
    func restoreARSession() {
        #if !os(visionOS)
        guard let worldMap = loadWorldMap() else {
            // No saved world map, start fresh
            startARSession()
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = worldMap
        
        arSession?.run(configuration, options: [.resetTracking])
        self.configuration = configuration
        sessionState = .running
        isCameraActive = true
        #else
        startARSession()
        #endif
    }
    
    // MARK: - Proximity Detection
    
    /// Start proximity detection timer
    private func startProximityDetection() {
        // Stop existing timer if running
        stopProximityDetection()
        
        // Create new timer for proximity checks
        proximityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkProximityToAnchors()
        }
    }
    
    /// Stop proximity detection timer
    private func stopProximityDetection() {
        proximityTimer?.invalidate()
        proximityTimer = nil
    }
    
    /// Check proximity to all anchors
    private func checkProximityToAnchors() {
        #if !os(visionOS)
        guard let arView = arView, sessionState == .running else {
            // If AR is not available, fall back to geolocation
            checkGeolocationProximity()
            return
        }
        
        // Get camera transform
        guard let cameraTransform = arSession?.currentFrame?.camera.transform else {
            return
        }
        
        // Check distance to each anchor
        var closestAnchor: AnchorViewModel?
        var closestDistance = Float.infinity
        
        for anchor in anchors {
            let distance = calculateDistance(from: cameraTransform, to: anchor.worldTransform)
            
            // If within proximity threshold (0.5 meters)
            if distance < 0.5 {
                if distance < closestDistance {
                    closestDistance = distance
                    closestAnchor = anchor
                }
            }
        }
        
        // Update active anchor if changed
        if closestAnchor != activeAnchor {
            let previousAnchor = activeAnchor
            activeAnchor = closestAnchor
            
            // Trigger notification for newly active anchor
            if let anchor = closestAnchor {
                triggerProximityNotification(for: anchor)
            }
            
            // Update visual feedback
            updateAnchorVisuals(previousAnchor: previousAnchor, newActiveAnchor: closestAnchor)
        }
        #else
        // visionOS proximity detection would use different methods
        // For example, spatial anchors or hand proximity
        #endif
    }
    
    /// Calculate distance between two transforms
    /// - Parameters:
    ///   - from: Source transform
    ///   - to: Target transform
    /// - Returns: Distance in meters
    private func calculateDistance(from: simd_float4x4, to: simd_float4x4) -> Float {
        let fromPosition = simd_make_float3(from.columns.3)
        let toPosition = simd_make_float3(to.columns.3)
        return simd_distance(fromPosition, toPosition)
    }
    
    /// Check proximity using geolocation (fallback when AR is not available)
    private func checkGeolocationProximity() {
        guard let userLocation = locationManager.location else { return }
        
        // In a real app, we would store geolocation with each anchor
        // and check proximity using CLLocation distance methods
    }
    
    /// Trigger notification when in proximity to an anchor
    /// - Parameter anchor: The anchor in proximity
    private func triggerProximityNotification(for anchor: AnchorViewModel) {
        // Notify the notification manager
        notificationManager?.triggerProximityNotification(for: anchor)
    }
    
    /// Update visuals for anchors based on proximity
    /// - Parameters:
    ///   - previousAnchor: The previously active anchor
    ///   - newActiveAnchor: The newly active anchor
    private func updateAnchorVisuals(previousAnchor: AnchorViewModel?, newActiveAnchor: AnchorViewModel?) {
        // Reset previous anchor visual
        if let previous = previousAnchor {
            resetAnchorVisual(for: previous.id)
        }
        
        // Highlight new active anchor
        if let active = newActiveAnchor {
            highlightAnchorVisual(for: active.id)
        }
    }
    
    /// Reset visual appearance of an anchor
    /// - Parameter anchorId: The ID of the anchor to reset
    private func resetAnchorVisual(for anchorId: UUID) {
        guard let visualEntity = visualEntities[anchorId] else { return }
        
        // Reset to normal appearance
        // For example, change color, scale, etc.
        visualEntity.scale = [1.0, 1.0, 1.0]
        
        if let material = visualEntity.model?.materials.first as? SimpleMaterial {
            var color = material.color
            color.tint = .blue
            material.color = color
        }
    }
    
    /// Highlight visual appearance of an anchor
    /// - Parameter anchorId: The ID of the anchor to highlight
    private func highlightAnchorVisual(for anchorId: UUID) {
        guard let visualEntity = visualEntities[anchorId] else { return }
        
        // Highlight appearance
        // For example, change color, scale, add animation, etc.
        visualEntity.scale = [1.5, 1.5, 1.5]
        
        if let material = visualEntity.model?.materials.first as? SimpleMaterial {
            var color = material.color
            color.tint = .green
            material.color = color
        }
        
        // Add pulsing animation
        let pulseAnimation = Animation.easeInOut(duration: 1.0).repeatForever()
        visualEntity.setScale([1.3, 1.3, 1.3], relativeTo: visualEntity.parent, duration: 1.0, timingFunction: .easeInOut)
    }
    
    // MARK: - Anchor Management
    
    /// Update an existing anchor
    /// - Parameters:
    ///   - anchor: The anchor view model to update
    ///   - iconType: New icon type (optional)
    func updateAnchor(anchor: AnchorViewModel, iconType: AnchorIconType? = nil) {
        guard let context = viewContext,
              let anchorObject = fetchAnchorObject(withId: anchor.id) else { return }
        
        if let iconType = iconType {
            anchorObject.iconType = iconType.rawValue
            
            // Update visual entity
            updateAnchorVisual(for: anchor.id, with: iconType)
        }
        
        do {
            try context.save()
            loadAnchors() // Reload to refresh view models
            
            // Notify that anchor data has changed
            NotificationCenter.default.post(name: .anchorDataChanged, object: nil)
        } catch {
            print("Failed to update anchor: \(error)")
        }
    }
    
    /// Update visual entity for an anchor
    /// - Parameters:
    ///   - anchorId: The ID of the anchor to update
    ///   - iconType: The new icon type
    private func updateAnchorVisual(for anchorId: UUID, with iconType: AnchorIconType) {
        guard let anchorEntity = anchorEntities[anchorId] else { return }
        
        // Remove old visual entity
        if let oldVisual = visualEntities[anchorId] {
            oldVisual.removeFromParent()
        }
        
        // Create new visual entity
        let newVisual = createVisualEntity(for: iconType)
        anchorEntity.addChild(newVisual)
        
        // Update cache
        visualEntities[anchorId] = newVisual
    }
    
    /// Delete an anchor
    /// - Parameter anchor: The anchor view model to delete
    func deleteAnchor(anchor: AnchorViewModel) {
        guard let context = viewContext,
              let anchorObject = fetchAnchorObject(withId: anchor.id) else { return }
        
        // Remove from AR scene
        removeAnchorFromScene(anchor.id)
        
        // Delete from Core Data
        context.delete(anchorObject)
        
        do {
            try context.save()
            
            // Remove from arrays
            if let index = anchors.firstIndex(where: { $0.id == anchor.id }) {
                anchors.remove(at: index)
            }
            
            // Update world map
            saveWorldMap()
            
            // Notify that anchor data has changed
            NotificationCenter.default.post(name: .anchorDataChanged, object: nil)
        } catch {
            print("Failed to delete anchor: \(error)")
        }
    }
    
    /// Remove an anchor from the AR scene
    /// - Parameter anchorId: The ID of the anchor to remove
    private func removeAnchorFromScene(_ anchorId: UUID) {
        #if !os(visionOS)
        guard let arView = arView,
              let anchorEntity = anchorEntities[anchorId] else { return }
        
        // Remove from scene
        arView.scene.removeAnchor(anchorEntity)
        
        // Remove from caches
        anchorEntities.removeValue(forKey: anchorId)
        visualEntities.removeValue(forKey: anchorId)
        #endif
    }
    
    // MARK: - Helper Methods
    
    /// Check AR availability on the device
    private func checkARAvailability() {
        isARAvailable = ARWorldTrackingConfiguration.isSupported
        
        if !isARAvailable {
            sessionErrorMessage = "AR is not supported on this device"
            sessionState = .failed
        }
    }
    
    /// Fetch a Habit object from Core Data by ID
    /// - Parameter id: The UUID of the habit to fetch
    /// - Returns: The Habit object if found, nil otherwise
    private func fetchHabitObject(withId id: UUID) -> Habit? {
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
    
    /// Fetch an Anchor object from Core Data by ID
    /// - Parameter id: The UUID of the anchor to fetch
    /// - Returns: The Anchor object if found, nil otherwise
    private func fetchAnchorObject(withId id: UUID) -> Anchor? {
        guard let context = viewContext else { return nil }
        
        let request: NSFetchRequest<Anchor> = Anchor.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Failed to fetch anchor with ID \(id): \(error)")
            return nil
        }
    }
    
    /// Get anchors for a specific habit
    /// - Parameter habitId: The habit ID to get anchors for
    /// - Returns: Array of anchor view models
    func getAnchorsForHabit(habitId: UUID) -> [AnchorViewModel] {
        return anchors.filter { $0.habitId == habitId }
    }
    
    /// Focus the AR view on a specific anchor
    /// - Parameter anchorId: The ID of the anchor to focus on
    func focusOnAnchor(anchorId: UUID) {
        guard let anchor = anchors.first(where: { $0.id == anchorId }) else { return }
        
        // Ensure AR session is running
        if sessionState != .running {
            startARSession()
        }
        
        // Highlight the anchor
        highlightAnchorVisual(for: anchorId)
        
        // Set as active anchor
        activeAnchor = anchor
        
        // In a real implementation, we would also adjust the camera view
        // to focus on this anchor
    }
}

// MARK: - ARSessionDelegate
extension AnchorManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process frame updates
        // This is called every frame and can be used for continuous tracking
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // Process added anchors
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                // Add to detected planes
                if !detectedPlanes.contains(where: { $0.identifier == planeAnchor.identifier }) {
                    detectedPlanes.append(planeAnchor)
                }
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Process updated anchors
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                // Update detected plane
                if let index = detectedPlanes.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                    detectedPlanes[index] = planeAnchor
                }
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        // Process removed anchors
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                // Remove from detected planes
                detectedPlanes.removeAll(where: { $0.identifier == planeAnchor.identifier })
            }
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // Handle tracking state changes
        switch camera.trackingState {
        case .normal:
            sessionState = .running
            sessionErrorMessage = nil
        case .limited(let reason):
            sessionState = .limited
            
            switch reason {
            case .initializing:
                sessionErrorMessage = "Initializing AR session..."
            case .excessiveMotion:
                sessionErrorMessage = "Too much motion. Slow down."
            case .insufficientFeatures:
                sessionErrorMessage = "Not enough visual features. Aim at a textured surface."
            case .relocalizing:
                sessionErrorMessage = "Relocalizing..."
            @unknown default:
                sessionErrorMessage = "Limited tracking quality."
            }
        case .notAvailable:
            sessionState = .failed
            sessionErrorMessage = "Tracking not available."
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle session failures
        sessionState = .failed
        sessionErrorMessage = "AR session failed: \(error.localizedDescription)"
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Handle session interruption
        sessionState = .interrupted
        sessionErrorMessage = "AR session interrupted. Please wait."
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Handle interruption end
        sessionState = .running
        sessionErrorMessage = nil
        
        // Reset tracking if needed
        resetARSession()
    }
}

// MARK: - CLLocationManagerDelegate
extension AnchorManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Use location updates for geofencing fallback
        if sessionState != .running {
            checkGeolocationProximity()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Handle region entry for geofencing
        if let circularRegion = region as? CLCircularRegion,
           let anchorId = UUID(uuidString: region.identifier),
           let anchor = anchors.first(where: { $0.id == anchorId }) {
            
            // Trigger proximity notification
            triggerProximityNotification(for: anchor)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let anchorDataChanged = Notification.Name("anchorDataChanged")
    static let focusOnAnchor = Notification.Name("focusOnAnchor")
}
