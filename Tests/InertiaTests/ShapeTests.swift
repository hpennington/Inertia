import XCTest
@testable import Inertia

/// The shapes an actionable's canvas draws: how they are authored alongside an
/// animation, and how they reach the renderer.
final class ShapeTests: XCTestCase {
    private func corner(_ x: Double, _ y: Double) -> Vertex {
        Vertex(
            position: InertiaPoint(x: x, y: y),
            color: InertiaColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
    }

    private func shapedCorner(_ x: Double, _ y: Double, _ red: Float, _ green: Float, _ blue: Float) -> Vertex {
        Vertex(
            position: InertiaPoint(x: x, y: y),
            color: InertiaColor(red: red, green: green, blue: blue, alpha: 0.6)
        )
    }

    private let identity = InertiaAnimationValues(scale: 1, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)

    /// A card with a shape behind it, taken through the animation file's own
    /// bytes rather than built in memory: what is being checked is that a shape
    /// survives being written and read back, so the coding has to be part of it.
    private func decodeDemo() throws -> [InertiaID: InertiaAnimationSchema] {
        let card0 = InertiaAnimationSchema(
            id: "card0",
            initialValues: identity,
            invokeType: .trigger,
            keyframes: [],
            shapes: [
                InertiaShape(id: "card0-shape", vertices: [
                    shapedCorner(0, 0, 0.35, 0.1, 0.85),
                    shapedCorner(1, 0, 0.1, 0.55, 0.95),
                    shapedCorner(1, 1, 0.1, 0.85, 0.75),
                    shapedCorner(0, 1, 0.35, 0.1, 0.85)
                ])
            ]
        )

        let card1 = InertiaAnimationSchema(
            id: "card1",
            initialValues: identity,
            invokeType: .auto,
            keyframes: []
        )

        let data = try InertiaCoding.encode([card0, card1])
        let schemas = try XCTUnwrap(decodeInertiaSchemas(data: data))
        return schemas.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    func testShapesAreDecodedWithTheirVertices() throws {
        let card0 = try XCTUnwrap(decodeDemo()["card0"])

        XCTAssertEqual(card0.shapes.count, 1)
        XCTAssertEqual(card0.shapes.first?.vertices.count, 4)
        XCTAssertEqual(card0.shapes.first?.vertices.first?.position, InertiaPoint(x: 0, y: 0))
        XCTAssertEqual(card0.shapes.first?.vertices.first?.color.alpha, 0.6)
    }

    /// An animation authored before shapes existed — or one that simply wants
    /// none — has to keep loading, or a single old file takes the whole
    /// container's schemas down with it.
    func testAnimationWithoutShapesStillDecodes() throws {
        /// A schema as it was written before shapes existed: the key is
        /// genuinely absent from the bytes rather than present and empty.
        /// Encoding the real type would always write the field, so the case
        /// needs a shape of its own to be tested at all.
        struct SchemaWithoutShapes: Encodable {
            let id: InertiaID
            let initialValues: InertiaAnimationValues
            let invokeType: InertiaAnimationInvokeType
            let keyframes: [InertiaAnimationKeyframe]
        }

        let data = try InertiaCoding.encode(
            SchemaWithoutShapes(id: "card1", initialValues: identity, invokeType: .auto, keyframes: [])
        )

        let card1 = try InertiaCoding.decode(InertiaAnimationSchema.self, from: data)

        XCTAssertEqual(card1.shapes, [])
    }

    /// Saving is the same schemas encoded straight back out, so a shape only
    /// lasts a session if it makes the round trip. Reading it and writing
    /// nothing is how an authored canvas gets quietly emptied by the first
    /// keyframe anyone records.
    func testShapesAreWrittenBackOut() throws {
        let decoded = try decodeDemo()
        let encoded = try InertiaCoding.encode(["card0", "card1"].compactMap { decoded[$0] })
        let reread = try XCTUnwrap(decodeInertiaSchemas(data: encoded))
            .reduce(into: [InertiaID: InertiaAnimationSchema]()) { $0[$1.id] = $1 }

        XCTAssertEqual(reread["card0"]?.shapes, decoded["card0"]?.shapes)
        XCTAssertEqual(reread["card1"]?.shapes, [])
    }

    /// A shape is a ring of corners; the renderer draws triangles. Four corners
    /// are the two triangles of a quad, sharing the corner the fan turns about.
    func testShapeIsTriangulatedAsAFan() throws {
        let corners = (0..<4).map { corner(Double($0), Double($0)) }

        let triangles = InertiaShape(id: "fan", vertices: corners).triangles

        XCTAssertEqual(triangles.count, 6)
        XCTAssertEqual(triangles.map(\.position.x), [0, 1, 2, 0, 2, 3])
    }

    /// A shape that fits the actionable exactly gives a canvas that is the
    /// actionable: the unit box, at its origin.
    func testBoundsOfAShapeFillingTheActionable() {
        let shape = InertiaShape(id: "filling", vertices: [corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1)])

        XCTAssertEqual([shape].bounds, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The point of fitting the canvas to the shapes: one reaching past the
    /// actionable grows the canvas instead of being cut off at its edge — at the
    /// actionable's own edge, or at the container's, which is what stopped a
    /// shape at the window before. 1.2 is a fifth of the actionable's width past
    /// its right edge, and -0.5 half its width before its left, so the canvas
    /// spans 1.7 of it.
    func testBoundsGrowToHoldShapesOutsideTheActionable() throws {
        let shape = InertiaShape(id: "overflowing", vertices: [corner(-0.5, 0), corner(1.2, 0), corner(1.2, 3)])

        let bounds = try XCTUnwrap([shape].bounds)

        XCTAssertEqual(bounds.minX, -0.5, accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 1.7, accuracy: 0.0001)
        XCTAssertEqual(bounds.height, 3, accuracy: 0.0001)
    }

    /// Several shapes share one canvas, so the box has to hold all of them.
    func testBoundsSpanEveryShape() {
        let left = InertiaShape(id: "left", vertices: [corner(-1, 0), corner(0, 0), corner(0, 1)])
        let right = InertiaShape(id: "right", vertices: [corner(1, 0), corner(2, 0), corner(2, 0.5)])

        XCTAssertEqual([left, right].bounds, CGRect(x: -1, y: 0, width: 3, height: 1))
    }

    /// Shapes enclosing no area have no canvas, which is also the state in which
    /// there is nothing to draw.
    func testBoundsOfEmptyOrDegenerateShapesAreNil() {
        XCTAssertNil([InertiaShape]().bounds)
        XCTAssertNil([InertiaShape(id: "empty", vertices: [])].bounds)
        XCTAssertNil([InertiaShape(id: "degenerate", vertices: [corner(1, 0), corner(1, 1)])].bounds)
    }

    /// Whatever box the canvas ends up being, the renderer is handed the shape
    /// in the canvas's own 0...1 space — so the corner that defined the far edge
    /// of the bounds lands exactly on it.
    func testShapeIsNormalizedIntoTheCanvasBounds() {
        let shape = InertiaShape(id: "normalized", vertices: [corner(-0.5, 0), corner(1.5, 0), corner(1.5, 2)])

        let normalized = shape.triangles(normalizedTo: CGRect(x: -0.5, y: 0, width: 2, height: 2))

        XCTAssertEqual(normalized[0].position, InertiaPoint(x: 0, y: 0))
        XCTAssertEqual(normalized[1].position, InertiaPoint(x: 1, y: 0))
        XCTAssertEqual(normalized[2].position, InertiaPoint(x: 1, y: 1))
    }

    /// Fewer than three corners enclose nothing, and handing the renderer a
    /// partial triangle would have it read past the end of the list.
    func testShapeWithTooFewCornersDrawsNothing() {
        XCTAssertEqual(InertiaShape(id: "no-corners", vertices: []).triangles, [])
        XCTAssertEqual(InertiaShape(id: "one-line", vertices: [corner(0, 0), corner(1, 1)]).triangles, [])
    }

    // MARK: - Shapes that carry an animation

    /// The other way a shape is authored: a drawn vector, described rather than
    /// spelled out corner by corner, with a track of its own attached — which is
    /// what makes it move independently of the actionable it is drawn behind.
    private func decodeDrawn() throws -> InertiaShape {
        func values(_ x: CGFloat, _ y: CGFloat) -> InertiaAnimationValues {
            InertiaAnimationValues(
                scale: 1,
                translate: CGSize(width: x, height: y),
                rotate: 0,
                rotateCenter: 0,
                opacity: 1
            )
        }

        let card2 = InertiaAnimationSchema(
            id: "card2",
            initialValues: identity,
            invokeType: .auto,
            keyframes: [],
            shapes: [
                InertiaShape(id: "card2-rectangle", shape: InertiaShapeProperties(id: "123", type: .rectangle, width: 2, height: 2, fill: InertiaColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)),
                    vertices: nil,
                    animation: InertiaAnimationSchema(
                        id: "shape0",
                        initialValues: identity,
                        invokeType: .auto,
                        keyframes: [
                            InertiaAnimationKeyframe(id: "a", values: values(0.8, 0.9), duration: 0.001),
                            InertiaAnimationKeyframe(id: "b", values: values(-0.02, -0.05), duration: 1.3)
                        ]
                    )
                )
            ]
        )

        let data = try InertiaCoding.encode([card2])
        let schemas = try XCTUnwrap(decodeInertiaSchemas(data: data))
        return try XCTUnwrap(schemas.first?.shapes.first)
    }

    /// A shape given a track keeps it: without this the vector is decoded and
    /// drawn, and then sits still because the only animation that reached the
    /// runtime was the actionable's.
    func testShapeCarriesItsOwnAnimation() throws {
        let animation = try XCTUnwrap(decodeDrawn().animation)

        XCTAssertEqual(animation.id, "shape0")
        XCTAssertEqual(animation.invokeType, .auto)
        XCTAssertEqual(animation.keyframes.count, 2)
        XCTAssertEqual(animation.keyframes.last?.values.translate.width, -0.02)
    }

    /// A described shape has no corners on the wire; the ones it is drawn from
    /// are worked out from the description. A rectangle is its four corners, and
    /// the fan that covers them is the two triangles of a quad.
    func testDescribedShapeIsDrawnFromItsDescription() throws {
        let shape = try decodeDrawn()

        XCTAssertNil(shape._vertices)
        XCTAssertEqual(shape.vertices.count, 4)
        XCTAssertEqual(shape.triangles.count, 6)
        XCTAssertNotNil([shape].bounds)
    }

    /// Normalizing is the last thing to touch a shape before the renderer, and
    /// what it hands over is the drawing rather than the outline — so everything
    /// the shape paints has to come through it, at the size the canvas is.
    func testNormalizingKeepsEverythingTheShapeDraws() throws {
        let shape = try decodeDrawn()
        let bounds = try XCTUnwrap([shape].bounds)

        let normalized = shape.triangles(normalizedTo: bounds)

        XCTAssertEqual(normalized.count, shape.triangles.count)
        XCTAssertEqual(normalized.map(\.color), shape.triangles.map(\.color))
        // The shape filled its own bounds, so normalizing lands it on the unit
        // box: every corner inside 0...1, and the far ones exactly on it.
        XCTAssertEqual(try XCTUnwrap(normalized.map(\.position.x).min()), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(normalized.map(\.position.x).max()), 1, accuracy: 0.0001)
    }

    /// The same round trip the authored corners make: a track attached to a
    /// shape only lasts a session if saving writes it back out.
    func testShapeAnimationIsWrittenBackOut() throws {
        let shape = try decodeDrawn()

        let encoded = try JSONEncoder().encode([shape])
        let reread = try JSONDecoder().decode([InertiaShape].self, from: encoded)

        XCTAssertEqual(reread.first, shape)
        XCTAssertEqual(reread.first?.animation?.keyframes.count, 2)
        XCTAssertEqual(reread.first?.shape?.type, .rectangle)
    }

    // MARK: - The vectors a description resolves to

    /// The box a described vector encloses, which is what says whether it came
    /// out the shape it was asked for.
    private func drawnBounds(_ type: InertiaShapeType, _ width: CGFloat, _ height: CGFloat) throws -> CGRect {
        let shape = InertiaShape(id: "drawn", shape: InertiaShapeProperties(
                id: "123",
                type: type,
                width: width,
                height: height,
                fill: InertiaColor(red: 1, green: 0, blue: 0, alpha: 1)
            ),
            vertices: nil
        )

        return try XCTUnwrap([shape].bounds)
    }

    /// The two descriptions that carry two measurements have to spend both. A
    /// rectangle sized by one of them is the bug this replaced: every vector
    /// came out square, whatever box it had been dragged out over.
    func testRectangleAndOvalFillTheBoxTheyWereDrawnIn() throws {
        for type in [InertiaShapeType.rectangle, .oval] {
            let bounds = try drawnBounds(type, 3, 1)

            XCTAssertEqual(bounds.width, 3, accuracy: 0.0001, "\(type)")
            XCTAssertEqual(bounds.height, 1, accuracy: 0.0001, "\(type)")
        }
    }

    /// The three descriptions with one measurement rather than two stay
    /// themselves whatever box they were drawn in — sized, all three, by its
    /// longer side.
    func testSquareCircleAndTriangleStayRegularInALopsidedBox() throws {
        for type in [InertiaShapeType.square, .circle, .triangle] {
            let bounds = try drawnBounds(type, 3, 1)

            XCTAssertEqual(bounds.width, 3, accuracy: 0.0001, "\(type)")
        }

        // The triangle is the one that isn't as tall as it is wide: it is drawn
        // as an equilateral one, so its height is the altitude of its base.
        XCTAssertEqual(try drawnBounds(.square, 3, 1).height, 3, accuracy: 0.0001)
        XCTAssertEqual(try drawnBounds(.circle, 3, 1).height, 3, accuracy: 0.0001)
        XCTAssertEqual(try drawnBounds(.triangle, 3, 1).height, 3 * sqrt(3) / 2, accuracy: 0.0001)
    }

    /// A round vector is drawn as the many-sided polygon that reads as one, and
    /// every one of those corners sits on the ellipse — which is what stops it
    /// being the squared-off box it used to be drawn as.
    func testOvalIsARingOfCornersOnItsEllipse() throws {
        let shape = InertiaShape(id: "oval", shape: InertiaShapeProperties(
                id: "123",
                type: .oval,
                width: 4,
                height: 2,
                fill: InertiaColor(red: 0, green: 0.5, blue: 1, alpha: 1)
            ),
            vertices: nil
        )

        XCTAssertEqual(shape.vertices.count, InertiaShapeProperties.ovalSegments)

        for vertex in shape.vertices {
            // x²/a² + y²/b² = 1, for a ring centred on the origin the
            // description is measured from.
            let position = vertex.position
            XCTAssertEqual(pow(position.x / 2, 2) + pow(position.y / 1, 2), 1, accuracy: 0.0001)
        }

        // The ring is convex, so the fan the renderer draws covers it exactly:
        // one triangle per corner but the two the fan turns about.
        XCTAssertEqual(shape.triangles.count, (InertiaShapeProperties.ovalSegments - 2) * 3)
    }

    /// The colour the description carries is the colour the corners come out,
    /// rather than the red placeholder every described vector used to be drawn
    /// in whatever the editor had recorded against it.
    func testDescribedShapeIsDrawnInItsOwnColor() throws {
        let shape = InertiaShape(id: "colored", shape: InertiaShapeProperties(
                id: "123",
                type: .rectangle,
                width: 1,
                height: 1,
                fill: InertiaColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
            ),
            vertices: nil
        )

        let corner = try XCTUnwrap(shape.vertices.first)

        XCTAssertEqual(corner.color.red, 0.25, accuracy: 0.0001)
        XCTAssertEqual(corner.color.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(corner.color.blue, 0.75, accuracy: 0.0001)
        XCTAssertEqual(corner.color.alpha, 0.5, accuracy: 0.0001)
    }

    // MARK: - Filling and stroking a described vector

    private func painted(
        _ type: InertiaShapeType = .rectangle,
        width: CGFloat = 2,
        height: CGFloat = 2,
        fill: InertiaColor? = nil,
        stroke: InertiaColor? = nil,
        strokeWidth: CGFloat = 0
    ) -> InertiaShape {
        InertiaShape(
            id: "painted",
            shape: InertiaShapeProperties(
                id: "123",
                type: type,
                width: width,
                height: height,
                fill: fill,
                stroke: stroke,
                strokeWidth: strokeWidth
            ),
            vertices: nil
        )
    }

    private let red = InertiaColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = InertiaColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// The two halves of painting a vector are independent: either alone is a
    /// shape, and neither drags the other along with it.
    func testFillAndStrokeAreDrawnIndependently() throws {
        let filled = painted(fill: red)
        let stroked = painted(stroke: blue, strokeWidth: 0.1)
        let both = painted(fill: red, stroke: blue, strokeWidth: 0.1)

        XCTAssertTrue(filled.triangles.allSatisfy { $0.color == red })
        XCTAssertTrue(stroked.triangles.allSatisfy { $0.color == blue })
        XCTAssertEqual(both.triangles.count, filled.triangles.count + stroked.triangles.count)

        // The fill first, so the outline is drawn over the area it encloses
        // rather than under it — the renderer blends straight down the list.
        XCTAssertEqual(both.triangles.prefix(filled.triangles.count).map(\.color), filled.triangles.map(\.color))
    }

    /// A shape with neither draws nothing, which is the one combination there is
    /// no reason to author — and a stroke colour with no width, or a width with
    /// no colour, is each half of an outline that was never asked for.
    func testShapeWithNothingToPaintWithDrawsNothing() {
        XCTAssertEqual(painted().triangles, [])
        XCTAssertEqual(painted(stroke: blue).triangles, [])
        XCTAssertEqual(painted(strokeWidth: 0.1).triangles, [])
    }

    /// The stroke is drawn inside the outline, so a shape occupies the box it
    /// was authored at whether or not it is stroked: adding an outline never
    /// moves the shape or grows the canvas fitted to it.
    func testStrokeIsDrawnInsideTheShapesOwnBox() throws {
        let plain = try XCTUnwrap([painted(fill: red)].bounds)
        let thick = try XCTUnwrap([painted(fill: red, stroke: blue, strokeWidth: 0.4)].bounds)

        XCTAssertEqual(thick, plain)

        // And nothing the stroke draws reaches past that box either.
        for vertex in painted(stroke: blue, strokeWidth: 0.4).triangles {
            XCTAssertTrue(plain.insetBy(dx: -0.0001, dy: -0.0001).contains(CGPoint(x: vertex.position.x, y: vertex.position.y)))
        }
    }

    /// The band is an even thickness all the way round, corners included: the
    /// inner ring of a stroked square is the square inset by the stroke on every
    /// side, which is what the mitre at each corner is for.
    func testStrokeIsAnEvenThicknessAroundTheShape() throws {
        let stroked = painted(.square, width: 2, height: 2, stroke: blue, strokeWidth: 0.25)

        // The outline runs ±1 from the centre; the inside of the band should run
        // ±0.75, and nothing should land between the two on both axes at once.
        let inner = stroked.triangles.filter { abs($0.position.x) < 0.9999 && abs($0.position.y) < 0.9999 }
        XCTAssertFalse(inner.isEmpty)

        for vertex in inner {
            XCTAssertEqual(Swift.max(abs(vertex.position.x), abs(vertex.position.y)), 0.75, accuracy: 0.0001)
        }
    }

    /// A stroke thicker than the shape has room for would turn the inner ring
    /// inside out — corners crossing past each other and the band folding back
    /// through itself. Held where the ring closes, which is a solid shape.
    func testStrokeThickerThanTheShapeIsDrawnSolid() {
        let overstroked = painted(.square, width: 2, height: 2, stroke: blue, strokeWidth: 10)

        // Every corner of the band is either on the outline or at the centre it
        // closed to; none of it has crossed to the far side.
        for vertex in overstroked.triangles {
            XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001)
            XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001)
        }
    }

    /// Every described vector can be stroked, not just the ones with corners:
    /// a round one is stroked around all 48 of the segments it is cut into, and
    /// a triangle around its three sharp corners.
    func testEveryDescribedVectorCanBeStroked() throws {
        for type in [InertiaShapeType.rectangle, .square, .circle, .oval, .triangle] {
            let stroked = painted(type, width: 3, height: 1, stroke: blue, strokeWidth: 0.1)
            let corners = stroked.vertices.count

            // Two triangles per edge of the outline, and the outline closes.
            XCTAssertEqual(stroked.triangles.count, corners * 6, "\(type)")
        }
    }

    /// A shape authored corner by corner carries its colour on the corners
    /// themselves, so it is all fill — stroking is something a *described*
    /// vector is asked for.
    func testShapeAuthoredCornerByCornerIsAllFill() {
        let shape = InertiaShape(id: "corners", vertices: [corner(0, 0), corner(1, 0), corner(1, 1)])

        XCTAssertEqual(shape.triangles.count, 3)
    }

    /// The palette and the wire format are one list: a vector the toolbar offers
    /// that no description can carry is a shape that cannot be drawn.
    func testEveryVectorInThePaletteIsADescribableShape() {
        XCTAssertEqual(InertiaVector.allCases.map(\.shapeType.rawValue), InertiaVector.allCases.map(\.rawValue))
    }
}
