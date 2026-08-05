import XCTest
import SwiftUI
@testable import Inertia

/// What the editor writes when a gesture on a shape is let go of, taken back
/// through the wire and read the way the app under test reads it.
///
/// A drag on a shape is only finished when the app it was made in draws the
/// shape where the drag left it: the runtime treats the gesture itself as
/// something that ends with the finger, and what holds the shape there
/// afterwards is the track the editor writes and hands straight back. These
/// cover the two steps that has to survive — the track reaching the runtime at
/// all, and reading back at the place it was authored once it has.
final class ShapeTrackRoundTripTests: XCTestCase {
    private func shape(track: InertiaAnimationSchema?) -> InertiaShape {
        InertiaShape(
            id: "circle",
            shape: InertiaShapeProperties(
                id: "circle-props",
                type: .circle,
                width: 0.5,
                height: 0.5,
                fill: InertiaColor(red: 1, green: 0, blue: 0, alpha: 1),
                stroke: nil,
                strokeWidth: 0
            ),
            vertices: nil,
            animation: track
        )
    }

    private var moved: InertiaAnimationValues {
        InertiaAnimationValues(
            scale: 1,
            translate: CGSize(width: 0.25, height: -0.1),
            rotate: 0,
            rotateCenter: 0,
            opacity: 1
        )
    }

    /// What `KeyframeHandler.recordShape` writes off the record: a track with the
    /// dragged values as its start and no keypoints at all.
    private var offTheRecordTrack: InertiaAnimationSchema {
        InertiaAnimationSchema(
            id: "circle-track",
            initialValues: moved,
            invokeType: .auto,
            keyframes: [],
            loopDuration: 3
        )
    }

    func testShapeTrackSurvivesTheWire() throws {
        let schema = InertiaAnimationSchema(
            id: "logo",
            initialValues: .identity,
            invokeType: .auto,
            keyframes: [],
            shapes: [shape(track: offTheRecordTrack)]
        )

        let data = try InertiaCoding.encode(schema)
        let decoded = try InertiaCoding.decode(InertiaAnimationSchema.self, from: data)
        let track = try XCTUnwrap(decoded.shapes.first?.animation, "the shape's track did not survive the wire")

        XCTAssertEqual(track.initialValues.translate.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(track.initialValues.translate.height, -0.1, accuracy: 0.0001)
    }

    /// What the runtime draws the shape at once that track has landed and its
    /// own gesture has been cleared.
    func testAnEmptyTrackReadsBackAtItsStartingValues() {
        let track = offTheRecordTrack

        // Not playing: the runtime returns the starting values outright.
        XCTAssertEqual(track.initialValues.translate.width, 0.25)

        // Playing, or with the actionable's own animation triggered, the shape is
        // read off the timeline instead — which for a track with no keypoints has
        // to be the same place.
        for time in [CGFloat(0), 0.5, 1.5, 2.9] {
            let sampled = track.values(at: time, filling: 3)
            XCTAssertEqual(
                sampled.translate.width, 0.25, accuracy: 0.0001,
                "a track with no keypoints moved the shape at t=\(time)"
            )
            XCTAssertEqual(sampled.scale, 1, accuracy: 0.0001, "scale drifted at t=\(time)")
            XCTAssertEqual(sampled.opacity, 1, accuracy: 0.0001, "opacity drifted at t=\(time)")
        }
    }
}
