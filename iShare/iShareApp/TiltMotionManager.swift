import CoreMotion
import Observation
import SwiftUI

/// Publishes live device tilt (roll/pitch) so glass surfaces can shift
/// their highlight as the phone moves, mimicking how real glass catches
/// light differently depending on the angle you view it from.
///
/// Uses CMMotionManager (raw attitude/gyro), not CMMotionActivityManager --
/// this does not require an NSMotionUsageDescription entry in Info.plist
/// or any permission prompt.
@Observable
@MainActor
final class TiltMotionManager {
    var roll: Double = 0
    var pitch: Double = 0

    private nonisolated(unsafe) let manager = CMMotionManager()

    init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.roll = motion.attitude.roll
            self.pitch = motion.attitude.pitch
        }
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}

/// Adds a light-catching edge to a glass shape that shifts position based
/// on live device tilt, so the highlight visibly moves as you rotate or
/// angle the phone.
struct TiltReactiveEdge: ViewModifier {
    var motion: TiltMotionManager
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.65),
                            .white.opacity(0.04),
                            .white.opacity(0.35)
                        ],
                        startPoint: UnitPoint(
                            x: 0.5 + CGFloat(motion.roll) * 0.7,
                            y: 0.5 + CGFloat(motion.pitch) * 0.7
                        ),
                        endPoint: UnitPoint(
                            x: 0.5 - CGFloat(motion.roll) * 0.7,
                            y: 0.5 - CGFloat(motion.pitch) * 0.7
                        )
                    ),
                    lineWidth: 1.25
                )
        )
    }
}

extension View {
    /// Call on any glass card to make its edge highlight react to device tilt.
    func tiltReactiveEdge(_ motion: TiltMotionManager, cornerRadius: CGFloat) -> some View {
        modifier(TiltReactiveEdge(motion: motion, cornerRadius: cornerRadius))
    }
}
