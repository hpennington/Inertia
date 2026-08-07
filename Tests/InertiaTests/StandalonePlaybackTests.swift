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
            inertiaSchemas: demoSchemas()
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

    /// A trigger is answered once. The run it asked for ends where the timeline
    /// comes round, and the animation is back at its initial values waiting to
    /// be asked again — rather than repeating for as long as the screen is up.
    func testATriggeredAnimationRetiresWhenTheTimelineComesRound() async throws {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: demoSchemas().filter { $0.value.invokeType == .trigger }
        )
        // Every track here is half a second long, which is what the loop is
        // padded out to and so how long one pass takes.
        model.loopDuration = 0.1

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")
        XCTAssertTrue(model.isRunning)

        try await Task.sleep(for: .milliseconds(800))

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
        XCTAssertFalse(model.isRunning, "nothing is left running off the clock")

        model.trigger("card0")
        XCTAssertEqual(model.states["card0"]?.trigger, true, "it has to be startable again")
        XCTAssertTrue(model.isRunning)
        XCTAssertNil(model.states["card0"]?.heldTime, "replaying lets go of the held frame")
    }

    /// What ends is the run, not what is on screen: the node stays on the frame
    /// the pass left it on rather than snapping back to where the track starts,
    /// and it is the next trigger that takes it back to the top.
    func testARetiredAnimationHoldsTheFrameItEndedOn() async throws {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: demoSchemas().filter { $0.value.invokeType == .trigger }
        )
        model.loopDuration = 0.1

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")

        try await Task.sleep(for: .milliseconds(800))

        // The end of the loop, which is the frame it was on as it came round —
        // and it is still read from the track, not from the initial values.
        XCTAssertEqual(model.states["card0"]?.heldTime, model.playbackDuration)
        XCTAssertEqual(model.trackTime(for: "card0"), model.playbackDuration)
    }

    /// The transport ends a pass wherever the playhead has got to, so nothing
    /// jumps at the moment it ends: the frame held is the frame drawn.
    func testPauseHoldsATriggeredAnimationWhereItWas() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")
        model.seek(to: 1.0)
        model.trigger("card0")

        model.pausePlayback()

        XCTAssertEqual(model.states["card0"]?.heldTime, 1.0)
        XCTAssertEqual(model.trackTime(for: "card0"), 1.0)
    }

    /// A held animation is not following the playhead any more — that is what
    /// makes it held — so scrubbing moves the rest of the screen around it.
    func testAHeldAnimationDoesNotFollowTheScrubber() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")
        model.pausePlayback()

        model.seek(to: 0.25)

        XCTAssertEqual(model.trackTime(for: "card0"), 0)
        XCTAssertEqual(model.trackTime(for: "card1"), 0.25, "the auto animation is scrubbed as usual")
    }

    /// An `auto` animation is not answering a trigger, so it plays the next pass
    /// rather than retiring at the end of one.
    func testAnAutoAnimationKeepsPlayingWhenTheTimelineComesRound() async throws {
        let model = makeModel()
        model.loopDuration = 0.1

        model.registerHierarchyIdPrefix("card1")

        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
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

    // MARK: - The editor's play button

    /// The play button starts what starts itself, and nothing else: a `trigger`
    /// animation is waiting on the app's `trigger(_:)` call, and playing the
    /// timeline is not that call.
    func testResumeStartsOnlyAutoAnimations() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")

        model.resumePlayback()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true, "a trigger animation waits for the app")
        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// The editor's Trigger action is the app's `trigger(_:)` call arriving over
    /// the socket, so it starts the animation the play button left waiting.
    func testTriggerSignalStartsATriggerAnimation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.resumePlayback()
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)

        model.trigger("card0")

        XCTAssertEqual(model.states["card0"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// Touching the transport ends a triggered pass: the play button asks for
    /// the run the timeline describes, which is the `auto` animations.
    func testResumeRetiresATriggeredAnimation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")
        model.trigger("card0")

        model.resumePlayback()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// The same on the way down. A pause parks the `auto` animations where they
    /// are; a triggered one is back at its initial values, waiting to be asked
    /// again.
    func testPauseRetiresATriggeredAnimation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")

        model.pausePlayback()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)

        model.trigger("card0")
        XCTAssertEqual(model.states["card0"]?.trigger, true)
    }

    /// The playhead put back to the start is the end of a pass however it got
    /// there — dragged there by hand as much as coming round on its own.
    func testSeekingToZeroRetiresATriggeredAnimation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")

        model.seek(to: 1.0)
        XCTAssertEqual(model.states["card0"]?.trigger, true, "a scrub across the loop is still the same pass")

        model.seek(to: 0)
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
    }

    /// The editor sends the schemas and then `resume` straight after, and the
    /// two can arrive the other way round: a signal is applied the moment it
    /// lands, a schema has to reach the model first. `resume` then finds nothing
    /// to start, and the `auto` animations have to start themselves when their
    /// schemas turn up.
    func testResumeBeforeSchemasStartsAutoAnimationsOnArrival() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: [:]
        )

        // `resume` overtakes the schemas: nothing is held yet, so it starts
        // nothing and the clock stays down.
        model.resumePlayback()
        XCTAssertFalse(model.isRunning)

        // The schemas land a tick later, the way `handleMessageSchema` delivers
        // them.
        model.inertiaSchemas = demoSchemas()
        model.startAutoAnimations()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }

    /// The playhead has to be released by the `resume` that started nothing,
    /// otherwise the schemas arriving behind it find it still parked and decline
    /// to start the run they were meant to join.
    func testResumeBeforeSchemasUnparksThePlayhead() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: [:]
        )

        model.seek(to: 1.0)
        XCTAssertNotNil(model.seekTime)

        model.resumePlayback()
        XCTAssertNil(model.seekTime)

        model.inertiaSchemas = demoSchemas()
        model.startAutoAnimations()

        XCTAssertTrue(model.isRunning)
    }

    /// A pause parks the playhead rather than putting the schemas back to
    /// waiting, so what arrives after one is marked as started and simply held
    /// there — the next play picks it up instead of starting a run under a
    /// transport that says it is stopped.
    func testSchemasArrivingWhilePausedDoNotStartTheClock() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: [:]
        )

        model.resumePlayback()
        model.pausePlayback()

        model.inertiaSchemas = demoSchemas()
        model.startAutoAnimations()

        XCTAssertFalse(model.isRunning, "a paused editor must not have the clock started under it")
        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
    }

    /// Playing starts what has not run, and leaves alone what the app has since
    /// cancelled — stopping one is the app's call.
    func testResumeDoesNotRestartCancelledAnimations() {
        let model = makeModel()

        // The `auto` card, which is the one `resume` would otherwise start.
        model.registerHierarchyIdPrefix("card1")
        model.cancel("card1")

        model.resumePlayback()

        XCTAssertTrue(model.isCancelled("card1"))
        XCTAssertNotEqual(model.states["card1"]?.trigger, true)
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

    // MARK: - Arriving on a screen

    /// The screen navigated to plays what it is meant to play by itself, which
    /// is the same set as anywhere else: the `auto` animations.
    func testRestartAllStartsAutoAnimations() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card1")
        model.seek(to: 1.0)

        model.restartAll()

        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.playheadTime, .zero)
        XCTAssertNil(model.seekTime)
    }

    /// Arriving on a screen is not the `trigger(_:)` call a `trigger` animation
    /// is waiting for. It sits at its initial values until the app makes it.
    func testRestartAllLeavesTriggerAnimationsWaiting() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")

        model.restartAll()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)

        model.trigger("card0")
        XCTAssertEqual(model.states["card0"]?.trigger, true)
    }

    /// A `trigger` animation that has already played goes back to the top when
    /// the screen it is on is arrived at again, rather than being left holding
    /// the last frame of the run it finished.
    func testRestartAllRewindsAPlayedTriggerAnimation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.trigger("card0")

        model.restartAll()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
    }

    /// A cancellation belongs to the screen it was made on: the app's next
    /// `trigger(_:)` after a navigation is answered rather than dropped.
    func testRestartAllClearsCancellation() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.cancel("card0")

        model.restartAll()

        XCTAssertFalse(model.isCancelled("card0"))
        XCTAssertEqual(model.states["card1"]?.trigger, true, "the auto animation plays whatever the app cancelled")
    }

    /// A screen of nothing but `trigger` animations has no run for the playhead
    /// to follow, and the editor should see its clock parked.
    func testRestartAllWithNothingToPlayLeavesTheClockDown() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: demoSchemas().filter { $0.value.invokeType == .trigger }
        )

        model.registerHierarchyIdPrefix("card0")
        model.restartAll()

        XCTAssertFalse(model.isRunning)
    }

    /// A navigation under a playing editor is still the app arriving on a
    /// screen: the `auto` animations play again from the top, and a `trigger`
    /// one goes back to waiting for the app whether or not it had been triggered
    /// on the screen just left.
    func testRestartAllLeavesTriggerAnimationsWaitingWhileTheEditorPlays() {
        let model = makeModel()

        model.registerHierarchyIdPrefix("card0")
        model.registerHierarchyIdPrefix("card1")
        model.trigger("card0")
        model.resumePlayback()

        model.restartAll()

        XCTAssertNotEqual(model.states["card0"]?.trigger, true)
        XCTAssertEqual(model.states["card1"]?.trigger, true)
        XCTAssertTrue(model.isRunning)
    }
}
