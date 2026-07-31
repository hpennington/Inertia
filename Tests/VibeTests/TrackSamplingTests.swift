import XCTest
import SwiftUI
@testable import Inertia

/// The track the runtime draws from, sampled at the playhead — the same thing
/// `InertiaEditable` does every frame, and what `InertiaActionable` has to do
/// too if a standalone app is to show what the editor showed.
final class TrackSamplingTests: XCTestCase {
    /// `card1` out of `example/demo.inertia/animations/animation.json`: the
    /// `auto` card, which starts at rest and ends most of the way across the
    /// container.
    private let card1 = InertiaAnimationSchema(
        id: "card1",
        initialValues: InertiaAnimationValues(scale: 1, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1),
        invokeType: .auto,
        keyframes: [
            InertiaAnimationKeyframe(
                id: "a",
                values: InertiaAnimationValues(
                    scale: 0.5,
                    translate: CGSize(width: -0.0024875621890547263, height: -0.01199657240788351),
                    rotate: 0,
                    rotateCenter: 0,
                    opacity: 1
                ),
                duration: 0.001
            ),
            InertiaAnimationKeyframe(
                id: "b",
                values: InertiaAnimationValues(
                    scale: 1,
                    translate: CGSize(width: -0.4444444444444444, height: 0.2506426735218508),
                    rotate: 0,
                    rotateCenter: 0,
                    opacity: 0.5
                ),
                duration: 1.499
            ),
        ]
    )

    private func timeline(for animation: InertiaAnimationSchema, loop: CGFloat) -> KeyframeTimeline<InertiaAnimationValues> {
        KeyframeTimeline(initialValue: animation.initialValues.sanitized) {
            KeyframeTrack {
                for keyframe in animation.keyframes(filling: loop) {
                    CubicKeyframe(keyframe.values, duration: keyframe.duration)
                }
            }
        }
    }

    /// The track is padded to the loop, so the whole loop is playable rather
    /// than only the 1.5s the keyframes cover.
    func testTrackIsPaddedToTheLoop() {
        let track = card1.keyframes(filling: 3.0)
        let total = track.reduce(CGFloat.zero) { $0 + $1.duration }

        XCTAssertEqual(track.count, 3) // two recorded, one hold
        XCTAssertEqual(total, 3.0, accuracy: 0.0001)
    }

    /// Sampling the timeline across the loop has to actually move: this is the
    /// value a standalone app would draw at each playhead position.
    func testSampledValuesMoveAcrossTheLoop() {
        let timeline = timeline(for: card1, loop: 3.0)

        let start = timeline.value(time: 0).sanitized
        let middle = timeline.value(time: 0.75).sanitized
        let end = timeline.value(time: 1.5).sanitized

        XCTAssertEqual(start.translate.width, 0, accuracy: 0.01)
        XCTAssertLessThan(middle.translate.width, -0.05, "midway through, the card should have moved left")
        XCTAssertEqual(end.translate.width, -0.4444, accuracy: 0.01)

        // And it stays out there for the rest of the loop rather than snapping
        // back. The hold is a keyframe like any other, so the spline still
        // overshoots into it before settling — hence the loose bound.
        let held = timeline.value(time: 2.5).sanitized
        XCTAssertEqual(held.translate.width, -0.4444, accuracy: 0.05)
    }
}
