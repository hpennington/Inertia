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

    // MARK: - Where a shape sits in its parent

    /// A square of the given size, placed by `transforms` — the two things that
    /// together say where a shape ends up.
    private func placed(
        _ size: CGFloat,
        _ transforms: InertiaAnimationValues?,
        shapes: [InertiaShape] = []
    ) -> InertiaShape {
        InertiaShape(
            id: "placed",
            shape: InertiaShapeProperties(id: "123", type: .rectangle, width: size, height: size, fill: red),
            vertices: nil,
            shapes: shapes,
            transforms: transforms
        )
    }

    private func moved(_ x: CGFloat, _ y: CGFloat) -> InertiaAnimationValues {
        InertiaAnimationValues(scale: 1, translate: CGSize(width: x, height: y), rotate: 0, rotateCenter: 0, opacity: 1)
    }

    /// A shape's corners are drawn about the origin of the box that holds it, so
    /// an unplaced one sits dead centre of its parent — which is where every
    /// shape authored before placements existed was drawn.
    func testShapeWithoutTransformsIsDrawnWhereItsCornersSay() throws {
        let bounds = try XCTUnwrap([placed(2, nil)].bounds)

        XCTAssertEqual(bounds.midX, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds.midY, 0, accuracy: 0.0001)
    }

    /// The whole point: the same shape said to sit somewhere else in its parent
    /// is drawn there, in fractions of that parent's own box.
    func testTransformsPlaceTheShapeInItsParent() throws {
        let bounds = try XCTUnwrap([placed(2, moved(0.5, -0.25))].bounds)

        XCTAssertEqual(bounds.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(bounds.midY, -0.25, accuracy: 0.0001)
        // Moved, not resized.
        XCTAssertEqual(bounds.width, 2, accuracy: 0.0001)
    }

    /// Scaling and turning happen about the point the shape was drawn around, so
    /// a shape left where it was authored grows about its own middle rather than
    /// sliding off across its parent.
    func testTransformsScaleAboutThePointTheShapeIsDrawnAround() throws {
        let scaled = InertiaAnimationValues(scale: 2, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)

        let bounds = try XCTUnwrap([placed(2, scaled)].bounds)

        XCTAssertEqual(bounds.width, 4, accuracy: 0.0001)
        XCTAssertEqual(bounds.midX, 0, accuracy: 0.0001)
    }

    /// A quarter turn of a square is the same square, and a shape moved *and*
    /// turned turns where it was drawn rather than swinging about its parent's
    /// middle: the rotation is applied before the move.
    func testTransformsTurnTheShapeWhereItWasPlaced() throws {
        let turned = InertiaAnimationValues(
            scale: 1,
            translate: CGSize(width: 0.5, height: 0),
            rotate: 90,
            rotateCenter: 0,
            opacity: 1
        )

        let bounds = try XCTUnwrap([placed(2, turned)].bounds)

        XCTAssertEqual(bounds.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(bounds.midY, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 2, accuracy: 0.0001)
    }

    /// The case a placement is really for: a nested shape is drawn into its
    /// parent's vertex buffer, so before this there was nothing that could move
    /// one — every child sat in the middle of its parent. The child's own units
    /// are its parent's box, so half of a parent two wide is one across.
    func testNestedShapeIsPlacedInItsParentsBox() throws {
        let child = placed(0.5, moved(0.5, 0))
        let parent = placed(2, nil, shapes: [child])

        let bounds = try XCTUnwrap([parent].bounds)

        // The parent spans ±1. The child is a quarter of the parent wide — 0.5
        // of a box two across — and sits half a parent-width from centre, so it
        // runs from 0.5 to 1.5 and hangs half of itself past the parent's edge.
        XCTAssertEqual(bounds.maxX, 1.5, accuracy: 0.0001)
        XCTAssertEqual(bounds.minX, -1, accuracy: 0.0001)
    }

    /// A child is part of its parent's drawing, so placing the parent carries
    /// everything inside it along.
    func testPlacingAParentCarriesItsChildren() throws {
        let child = placed(0.5, moved(0.5, 0))
        let stationary = try XCTUnwrap([placed(2, nil, shapes: [child])].bounds)
        let moved = try XCTUnwrap([placed(2, self.moved(3, 0), shapes: [child])].bounds)

        XCTAssertEqual(moved.minX - stationary.minX, 3, accuracy: 0.0001)
        XCTAssertEqual(moved.width, stationary.width, accuracy: 0.0001)
    }

    // MARK: - The box one shape occupies

    /// A square of the given size under a name of its own, so a drawing can be
    /// asked about one of the shapes in it.
    private func named(
        _ id: InertiaID,
        _ size: CGFloat,
        _ transforms: InertiaAnimationValues? = nil,
        shapes: [InertiaShape] = []
    ) -> InertiaShape {
        InertiaShape(
            id: id,
            shape: InertiaShapeProperties(id: "\(id)-properties", type: .rectangle, width: size, height: size, fill: red),
            vertices: nil,
            shapes: shapes,
            transforms: transforms
        )
    }

    /// What a selection border is fitted to: one shape's own box, in the same
    /// units the canvas holding the whole drawing is measured in — so the border
    /// fences in the vector that was picked rather than everything beside it.
    func testBoundsOfOneShapeAreItsOwnAndNotTheDrawings() throws {
        let drawing = [named("left", 1, moved(-2, 0)), named("right", 1, moved(2, 0))]

        let box = try XCTUnwrap(drawing.bounds(of: "right"))

        XCTAssertEqual(box.midX, 2, accuracy: 0.0001)
        XCTAssertEqual(box.width, 1, accuracy: 0.0001)
        // The drawing around it spans both, from -2.5 to 2.5.
        XCTAssertEqual(try XCTUnwrap(drawing.bounds).width, 5, accuracy: 0.0001)
    }

    /// A nested shape is measured in its parent's box and placed by it, so its
    /// own box only means anything once it has been carried back up — the same
    /// numbers `testNestedShapeIsPlacedInItsParentsBox` arrives at from the
    /// outside.
    func testBoundsOfANestedShapeAreInTheDrawingsUnits() throws {
        let child = named("child", 0.5, moved(0.5, 0))
        let parent = named("parent", 2, nil, shapes: [child])

        let box = try XCTUnwrap([parent].bounds(of: "child"))

        XCTAssertEqual(box.width, 1, accuracy: 0.0001)
        XCTAssertEqual(box.midX, 1, accuracy: 0.0001)
    }

    /// Placing the parent moves the box of everything inside it, because that is
    /// where those shapes are now drawn.
    func testBoundsOfANestedShapeFollowItsParentsPlacement() throws {
        let child = named("child", 0.5, moved(0.5, 0))
        let stationary = try XCTUnwrap([named("parent", 2, nil, shapes: [child])].bounds(of: "child"))
        let shifted = try XCTUnwrap([named("parent", 2, moved(3, 0), shapes: [child])].bounds(of: "child"))

        XCTAssertEqual(shifted.midX - stationary.midX, 3, accuracy: 0.0001)
        XCTAssertEqual(shifted.width, stationary.width, accuracy: 0.0001)
    }

    /// Nothing to point at: a shape that was hidden is not among the ones handed
    /// over, and a shape that was deleted is nowhere at all.
    func testBoundsOfAShapeThatIsNotInTheDrawingAreNil() {
        XCTAssertNil([named("only", 1)].bounds(of: "missing"))
        XCTAssertNil([InertiaShape]().bounds(of: "only"))
    }

    // MARK: - The box a shape is placed in

    /// A step authored into one shape's placement, carried into the drawing's
    /// own units by what `placementSpace(of:)` says that placement is measured
    /// in — the arithmetic the editor's canvas does to turn a drag into a
    /// placement, in the space this package answers questions in.
    private func step(
        _ drawing: [InertiaShape],
        placing id: InertiaID,
        by move: CGSize
    ) throws -> CGSize {
        let space = try XCTUnwrap(drawing.placementSpace(of: id))
        let before = try XCTUnwrap(drawing.bounds(of: id))

        // The move restated in the shape's own placement — out through the turn
        // and the scale its parents carry it through, then into their units.
        let authored = InertiaToolEdit(translate: space.values.unapplying(move))
        let shape = try XCTUnwrap(Self.locate(id, in: drawing))
        let placed = shape.placement.applying(
            authored,
            containerSize: CGSize(width: space.unit, height: space.unit)
        )

        let after = try XCTUnwrap(Self.replacing(placed, on: id, in: drawing).bounds(of: id))

        return CGSize(width: after.midX - before.midX, height: after.midY - before.midY)
    }

    private static func locate(_ id: InertiaID, in shapes: [InertiaShape]) -> InertiaShape? {
        for shape in shapes {
            if shape.id == id { return shape }
            if let found = locate(id, in: shape.shapes) { return found }
        }

        return nil
    }

    private static func replacing(
        _ transforms: InertiaAnimationValues,
        on id: InertiaID,
        in shapes: [InertiaShape]
    ) -> [InertiaShape] {
        shapes.map { shape in
            if shape.id == id { return shape.with(transforms: transforms) }

            return shape.with(shapes: replacing(transforms, on: id, in: shape.shapes))
        }
    }

    /// A shape on the actionable's own canvas is placed in the drawing itself,
    /// so its placement is already in the units everything around it is measured
    /// in and points the way they do.
    func testShapeOnTheCanvasIsPlacedInTheDrawingsOwnBox() throws {
        let space = try XCTUnwrap([named("solo", 1)].placementSpace(of: "solo"))

        XCTAssertEqual(space, .own)
    }

    /// A nested shape is placed in its parent's box, which is `childUnit` of the
    /// drawing across — so an authored step of one carries it that far.
    func testNestedShapeIsPlacedInItsParentsUnits() throws {
        let drawing = [named("parent", 2, nil, shapes: [named("child", 0.5)])]

        let space = try XCTUnwrap(drawing.placementSpace(of: "child"))

        XCTAssertEqual(space.unit, 2, accuracy: 0.0001)
        XCTAssertEqual(space.values, .identity)
    }

    /// Every box between the shape and the drawing, multiplied together: a
    /// grandchild is placed in a box that is a fraction of a fraction.
    func testDeeplyNestedShapeIsPlacedThroughEveryBox() throws {
        let grandchild = named("grandchild", 0.5)
        let drawing = [named("parent", 2, nil, shapes: [named("child", 0.5, nil, shapes: [grandchild])])]

        let space = try XCTUnwrap(drawing.placementSpace(of: "grandchild"))

        // The grandchild is placed in the child's box, and the child is 0.5 of a
        // parent 2 across — so that box is 1 of the drawing's units, not the 2
        // the child itself is placed in.
        XCTAssertEqual(space.unit, 1, accuracy: 0.0001)
    }

    /// A placement is baked into the corners, so a parent's own placement is
    /// part of the trip its children's placements take: a child inside a parent
    /// scaled by two is drawn twice as far along for the same authored step.
    ///
    /// This is what the editor's canvas moves a picked vector by. Counting the
    /// units alone sent a nested vector off at twice the speed of the pointer
    /// under a scaled parent, and sideways under a turned one.
    func testNestedShapeIsPlacedThroughItsParentsOwnPlacement() throws {
        let scaled = InertiaAnimationValues(scale: 2, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)
        let drawing = [named("parent", 2, scaled, shapes: [named("child", 0.5)])]

        let space = try XCTUnwrap(drawing.placementSpace(of: "child"))

        XCTAssertEqual(space.values.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(space.unit, 2, accuracy: 0.0001)
    }

    /// A parent's turn goes with its scale, and both compound down the branch.
    func testPlacementSpaceComposesEveryParentsTurnAndScale() throws {
        let turned = InertiaAnimationValues(scale: 2, translate: .zero, rotate: 30, rotateCenter: 15, opacity: 1)
        let grandchild = named("grandchild", 0.5)
        let drawing = [named("parent", 2, turned, shapes: [named("child", 0.5, turned, shapes: [grandchild])])]

        let space = try XCTUnwrap(drawing.placementSpace(of: "grandchild"))

        XCTAssertEqual(space.values.scale, 4, accuracy: 0.0001)
        XCTAssertEqual(space.values.rotate, 60, accuracy: 0.0001)
        XCTAssertEqual(space.values.rotateCenter, 30, accuracy: 0.0001)
    }

    func testPlacementSpaceOfAShapeThatIsNotInTheDrawingIsNil() {
        XCTAssertNil([named("only", 1)].placementSpace(of: "missing"))
        XCTAssertNil([InertiaShape]().placementSpace(of: "only"))
    }

    /// What the whole thing is for: a step measured on the drawing, authored
    /// into a shape's placement through the space it is placed in, moves the
    /// shape by exactly that step — wherever it is nested, and whatever its
    /// parents have been placed at.
    func testAStepAuthoredThroughThePlacementSpaceLandsWhereItWasAimed() throws {
        let move = CGSize(width: 0.5, height: -0.25)

        let solo: [InertiaShape] = [named("solo", 1)]
        let unplaced = [named("parent", 2, nil, shapes: [named("child", 0.5)])]
        let shifted = [named("parent", 2, moved(1.5, 0), shapes: [named("child", 0.5)])]
        let scaled = [
            named(
                "parent",
                2,
                InertiaAnimationValues(scale: 2, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1),
                shapes: [named("child", 0.5)]
            )
        ]
        let turned = [
            named(
                "parent",
                2,
                InertiaAnimationValues(scale: 1, translate: .zero, rotate: 90, rotateCenter: 0, opacity: 1),
                shapes: [named("child", 0.5)]
            )
        ]
        let deep = [named("parent", 2, nil, shapes: [named("child", 0.5, nil, shapes: [named("grandchild", 0.5)])])]

        for (name, drawing, id) in [
            ("on the canvas", solo, InertiaID("solo")),
            ("in an unplaced parent", unplaced, "child"),
            ("in a moved parent", shifted, "child"),
            ("in a scaled parent", scaled, "child"),
            ("in a turned parent", turned, "child"),
            ("two levels down", deep, "grandchild"),
        ] {
            let landed = try step(drawing, placing: id, by: move)

            XCTAssertEqual(landed.width, move.width, accuracy: 0.0001, "across, \(name)")
            XCTAssertEqual(landed.height, move.height, accuracy: 0.0001, "down, \(name)")
        }
    }

    /// A placement fades the shape through the corners' own alpha, since it has
    /// to survive being flattened into a buffer shared with shapes that are not
    /// faded.
    func testPlacementFadesTheShapeThroughItsCorners() throws {
        let faded = InertiaAnimationValues(scale: 1, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 0.5)

        let corner = try XCTUnwrap(placed(2, faded).triangles.first)

        XCTAssertEqual(corner.color.alpha, 0.5, accuracy: 0.0001)
    }

    /// A placement only lasts a session if saving writes it back out — and an
    /// animation authored before placements existed has to keep loading, drawn
    /// where its corners always said.
    func testTransformsSurviveTheRoundTrip() throws {
        let encoded = try InertiaCoding.encode([placed(2, moved(0.5, -0.25)), placed(2, nil)])
        let reread = try InertiaCoding.decode([InertiaShape].self, from: encoded)

        XCTAssertEqual(reread.first?.transforms, moved(0.5, -0.25))
        XCTAssertNil(reread.last?.transforms)
    }

    /// The palette and the wire format are one list: a vector the toolbar offers
    /// that no description can carry is a shape that cannot be drawn.
    func testEveryVectorInThePaletteIsADescribableShape() {
        XCTAssertEqual(InertiaVector.allCases.map(\.shapeType.rawValue), InertiaVector.allCases.map(\.rawValue))
    }

    // MARK: - The shape a press lands on

    private func point(_ x: Double, _ y: Double) -> InertiaPoint {
        InertiaPoint(x: x, y: y)
    }

    /// A described vector of the given type under a name of its own, filled
    /// unless it was asked for as an outline.
    private func drawn(
        _ id: InertiaID,
        _ type: InertiaShapeType,
        _ size: CGFloat,
        stroke: CGFloat = 0,
        transforms: InertiaAnimationValues? = nil,
        zIndex: Int = 0,
        shapes: [InertiaShape] = []
    ) -> InertiaShape {
        InertiaShape(
            id: id,
            shape: InertiaShapeProperties(
                id: "\(id)-properties",
                type: type,
                width: size,
                height: size,
                fill: stroke > 0 ? nil : red,
                stroke: stroke > 0 ? red : nil,
                strokeWidth: stroke
            ),
            vertices: nil,
            shapes: shapes,
            zIndex: zIndex,
            transforms: transforms
        )
    }

    /// The middle of a shape is the shape. The whole of picking one by touching
    /// it rests on this.
    func testPressOnAShapeFindsIt() {
        XCTAssertEqual([drawn("square", .square, 1)].hitTest(point(0, 0))?.id, "square")
    }

    /// What a bounding box would have got wrong, and the reason the artwork is
    /// tested rather than the box around it: the corner of a circle's box is not
    /// the circle, so a press there has to go on through to whatever is behind.
    func testPressInTheCornerOfARoundShapesBoxMissesIt() {
        let circle = [drawn("circle", .circle, 1)]

        // Just inside the box, which spans ±0.5 in both directions, and well
        // outside the radius of 0.5 that the circle actually fills.
        XCTAssertNil(circle.hitTest(point(0.49, 0.49)))
        XCTAssertEqual(circle.hitTest(point(0.4, 0))?.id, "circle")
    }

    /// A shape drawn as its outline alone encloses nothing in the middle, so a
    /// press through the hole falls to what is behind it rather than sticking to
    /// the ring around it.
    func testPressThroughAnUnfilledShapeMissesIt() {
        let ring = [drawn("ring", .square, 1, stroke: 0.1)]

        XCTAssertNil(ring.hitTest(point(0, 0)))
        // On the band itself, which runs the 0.1 inside the edge at 0.5.
        XCTAssertEqual(ring.hitTest(point(0.45, 0))?.id, "ring")
    }

    /// Nothing under the finger at all.
    func testPressOutsideEveryShapeFindsNothing() {
        XCTAssertNil([drawn("square", .square, 1)].hitTest(point(4, 4)))
        XCTAssertNil([InertiaShape]().hitTest(point(0, 0)))
    }

    /// Two shapes over one another hand the press to the one on top, which is
    /// the one the z-indexes draw last — not the one written first.
    func testPressOnOverlappingShapesPicksTheOneDrawnOnTop() {
        let drawing = [
            drawn("under", .square, 1, zIndex: 5),
            drawn("over", .square, 1, zIndex: 9)
        ]

        XCTAssertEqual(drawing.hitTest(point(0, 0))?.id, "over")
        XCTAssertEqual(drawing.reversed().hitTest(point(0, 0))?.id, "over")
    }

    /// A press is tested against where a shape is *drawn*, not where its corners
    /// were authored: a placement moves the shape, and it has to move what
    /// answers for it.
    func testPressFollowsAPlacedShape() {
        let shifted = [drawn("square", .square, 1, transforms: moved(2, 0))]

        XCTAssertNil(shifted.hitTest(point(0, 0)))
        XCTAssertEqual(shifted.hitTest(point(2, 0))?.id, "square")
    }

    /// Turning is undone as well as moving, and in the right order — the shape
    /// is turned where it was drawn and only then moved there, so unwinding the
    /// move first is what puts the press back on the artwork.
    func testPressFollowsATurnedAndMovedShape() {
        let turned = InertiaAnimationValues(
            scale: 1,
            translate: CGSize(width: 2, height: 0),
            rotate: 45,
            rotateCenter: 0,
            opacity: 1
        )

        // A rectangle twice as wide as it is tall, turned a half-turn short of
        // upright: its long axis now runs diagonally from where it was moved to.
        let shape = InertiaShape(
            id: "bar",
            shape: InertiaShapeProperties(id: "bar-properties", type: .rectangle, width: 4, height: 0.5, fill: red),
            vertices: nil,
            transforms: turned
        )

        let corner = 2 * cos(Double.pi / 4)

        XCTAssertEqual([shape].hitTest(point(2 + corner * 0.9, corner * 0.9))?.id, "bar")
        // The same distance out along the axis the bar is no longer on.
        XCTAssertNil([shape].hitTest(point(2 + corner * 0.9, -corner * 0.9)))
    }

    /// A nested shape is drawn into its parent's vertex buffer and has no canvas
    /// of its own, but it is a row of its own in the editor's hierarchy — so a
    /// press on it has to name the child rather than the parent it was drawn
    /// inside of.
    func testPressOnANestedShapeFindsTheChild() {
        let child = drawn("child", .square, 0.25, transforms: moved(0.3, 0))
        let parent = [drawn("parent", .square, 2, shapes: [child])]

        // The child is a quarter of the parent's box wide — 0.5 across — and
        // sits 0.6 out from the middle of a parent two wide.
        XCTAssertEqual(parent.hitTest(point(0.6, 0))?.id, "child")
        // Parent where the child is not.
        XCTAssertEqual(parent.hitTest(point(-0.6, 0))?.id, "parent")
    }

    /// A press misses a shape scaled away to nothing, which is also a shape with
    /// no area left to draw.
    func testPressMissesAShapeScaledToNothing() {
        let gone = InertiaAnimationValues(scale: 0, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)

        XCTAssertNil([drawn("square", .square, 1, transforms: gone)].hitTest(point(0, 0)))
    }
}
