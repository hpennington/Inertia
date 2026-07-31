import XCTest
@testable import Inertia

/// Playback with no editor attached (`dev: false`), where the schemas come off
/// disk rather than over the socket. Nothing here touches the websocket client:
/// an app in the field has no editor to report to, and it still has to animate.
@MainActor
final class StandalonePlaybackTests: XCTestCase {
    /// The shape `example/demo.inertia/animations/animation.json` has: the
    /// container itself with no track, one `trigger` card and one `auto` card.
    private func demoSchemas() -> [InertiaID: InertiaAnimationSchema] {
        let values = InertiaAnimationValues(
            scale: 1.0,
            translate: CGSize(width: 0.2, height: 0),
            rotate: 0,
            rotateCenter: 0,
            opacity: 1.0
        )

        return [
            "animation": InertiaAnimationSchema(
                id: "animation",
                initialValues: .zero,
                invokeType: .trigger,
                keyframes: []
            ),
            "card0": InertiaAnimationSchema(
                id: "card0",
                initialValues: .zero,
                invokeType: .trigger,
                keyframes: [InertiaAnimationKeyframe(id: "k0", values: values, duration: 0.5)]
            ),
            "card1": InertiaAnimationSchema(
                id: "card1",
                initialValues: .zero,
                invokeType: .auto,
                keyframes: [InertiaAnimationKeyframe(id: "k1", values: values, duration: 0.5)]
            ),
        ]
    }

    private func makeModel() -> InertiaDataModel {
        InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: demoSchemas(),
            tree: Tree(id: "animation"),
            actionableIdPairs: []
        )
    }

    /// An `auto` animation starts itself as soon as its actionable registers,
    /// which in a standalone app is the only thing that ever will.
    func testAutoStartsOnRegistration() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card1")

        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// A `trigger` animation waits, and starts when the app asks for it.
    func testTriggerWaitsThenStarts() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)

        model.trigger("card0")
        XCTAssertEqual(model.states["card0"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// Registering the `trigger` card must not start it just because the `auto`
    /// card got the clock going.
    func testAutoDoesNotStartTriggerAnimations() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")

        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
    }

    /// Cancelling stops the animation and leaves it stopped: `trigger(_:)` does
    /// not pick it back up.
    func testCancelStopsAndSticks() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")

        model.cancel("card0")
        XCTAssertTrue(model.isCancelled("card0"))
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)

        model.trigger("card0")
        XCTAssertTrue(model.isCancelled("card0"))
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
    }

    /// The clock stops with the last animation running off it. Registering
    /// `card0` starts `card1` too — `auto` animations do not wait to be
    /// registered — so both have to go before the playhead has nothing to follow.
    func testCancellingTheLastAnimationStopsTheClock() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")
        XCTAssertTrue(model.isRunning)

        model.cancel("card0")
        model.cancel("card1")

        XCTAssertFalse(model.isRunning)
    }

    /// The clock keeps going for whatever is still running when one of several
    /// animations is cancelled.
    func testCancelLeavesOtherAnimationsRunning() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")
        model.trigger("card0")

        model.cancel("card0")

        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// Restarting is what picks a cancelled animation back up, and what plays a
    /// running one from the top.
    func testRestartClearsCancellationAndRewinds() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")
        model.cancel("card0")

        model.restart("card0")
        XCTAssertFalse(model.isCancelled("card0"))
        XCTAssertEqual(model.states["card0"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.playheadTime, .zero)
    }
}
