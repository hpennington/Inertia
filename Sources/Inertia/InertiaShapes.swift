//
//  InertiaShapes.swift
//  
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

/// The kinds of vector a shape can be described as, rather than spelled out
/// corner by corner. A bare string on the wire, like every other enum here.
public enum InertiaShapeType: String, Codable {
    case rectangle
    case square
    case circle
    case oval
    case triangle
}

/// Which side of the actionable's own content a shape is drawn on.
///
/// A shape has always been a backdrop: drawn behind whatever the view renders,
/// so the label over it stays readable and the drawing stays a drawing. `top` is
/// that same shape put in front instead — a badge, a highlight, a scribble over
/// the view rather than under it — and it is the same canvas either way, hung
/// off the view as an overlay instead of a background.
///
/// This sits above `zIndex` rather than beside it: a z-index orders the shapes
/// drawn on one side of the content, and nothing drawn behind a view can be
/// lifted in front of it by counting higher.
public enum InertiaShapePosition: String, Codable, Sendable, CaseIterable {
    /// Behind the actionable's content — where every shape authored before this
    /// existed was drawn, which is why it is what an absent `position` means.
    case bottom
    /// Over the actionable's content.
    case top
}

/// A drawn vector as the editor records it: what it is, how big, and how it is
/// painted — the size in the same multiples of the actionable its corners would
/// have been measured in.
///
/// Painting is the two halves a vector has always had everywhere else: `fill`
/// floods the area the outline encloses, `stroke` draws the outline itself, and
/// either may be left out. A shape with no fill is an outline on nothing; a
/// shape with no stroke is the flat area a described vector used to be; a shape
/// with neither draws nothing at all, which is the one combination there is no
/// reason to author.
public struct InertiaShapeProperties: Codable, Equatable {
    public let id: InertiaID
    public let type: InertiaShapeType
    public let width: CGFloat
    public let height: CGFloat

    /// The colour flooding the outline, or nil for a shape that is only its
    /// outline.
    public let fill: InertiaColor?

    /// The colour of the outline itself, or nil for a shape that is only its
    /// area. Draws nothing without a `strokeWidth` to draw it at.
    public let stroke: InertiaColor?

    /// How thick the outline is, in the units the shape is sized in — multiples
    /// of the actionable's shorter side, the same as `width` and `height`, so a
    /// stroke keeps its weight relative to the shape at every size that frame
    /// takes, and is the same weight across as it is down.
    ///
    /// The stroke is drawn *inside* the outline: a shape occupies exactly the
    /// box it was authored at whether or not it is stroked, so adding a stroke
    /// never moves the shape or grows the canvas it is drawn on. A width past
    /// half the shape's smaller side would turn the ring inside out, so it is
    /// held there — a stroke that thick is a solid shape, and is drawn as one.
    public let strokeWidth: CGFloat

    public init(
        id: InertiaID,
        type: InertiaShapeType,
        width: CGFloat,
        height: CGFloat,
        fill: InertiaColor? = nil,
        stroke: InertiaColor? = nil,
        strokeWidth: CGFloat = 0
    ) {
        self.id = id
        self.type = type
        self.width = width
        self.height = height
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case width
        case height
        case fill
        case stroke
        case strokeWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(InertiaID.self, forKey: .id)
        type = try container.decode(InertiaShapeType.self, forKey: .type)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        fill = try container.decodeIfPresent(InertiaColor.self, forKey: .fill)
        stroke = try container.decodeIfPresent(InertiaColor.self, forKey: .stroke)
        // Absent is the unstroked shape rather than a malformed one, so a vector
        // authored as a plain fill is written without either stroke key.
        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
    }
}

/// A shape as it is authored alongside an animation: a ring of corners, each
/// carrying its own colour, measured against the actionable it belongs to —
/// (0, 0) the middle of that view, and 1 its shorter side.
///
/// One side rather than each of them, so a shape is drawn in a square space and
/// keeps the proportions it was described with: a circle of size 1 is round on a
/// view of any shape, and only a rectangle or an oval — the two descriptions
/// that say both of their measurements — is drawn wider than it is tall. See
/// `InertiaShapesView.unit`.
///
/// Nothing holds a shape to that box, though. Coordinates outside -0.5...0.5
/// reach past the actionable and go on being drawn, because the canvas they land
/// on is the container's rather than the view's: a shape three times the size of
/// the card it backs is authored simply by saying 3.
///
/// A shape may also carry an animation of its own, which is what makes it a
/// drawing rather than a backdrop: the corners say what is drawn, the animation
/// says how it moves, and the actionable it was authored against carries both.
public final class InertiaShape: Codable, Equatable, Identifiable, CustomStringConvertible {
    public static func ==(lhs: InertiaShape, rhs: InertiaShape) -> Bool {
        return lhs.id == rhs.id
            && lhs.vertices == rhs.vertices
            && lhs.transforms == rhs.transforms
            && lhs.animation == rhs.animation
            && lhs.shapes == rhs.shapes
            // Two shapes drawn at different times are not the same shape: this
            // one decides whether the shape is on screen at all, and a schema
            // arriving with it flipped has to redraw the canvas it belongs to.
            && lhs.showsBeforeAnimation == rhs.showsBeforeAnimation
    }

    public var description: String {
        """
        {"id": \(id), "vertices": \(vertices.count), "animated": \(animation != nil)}
        """
    }

    /// What this shape is, to anything that has to point at it: the editor's
    /// hierarchy panel, the selection sent back to the runtime, and the edit
    /// that selection authors.
    ///
    /// A shape used to be addressable only by where it sat — whose schema held
    /// it, and how far down the list — which is a name that changes when the
    /// shape either side of it is deleted. This does not.
    public let id: InertiaID

    /// Where this shape sits in the stack among the shapes it shares a list with
    /// — its siblings on an actionable's canvas, or the ones drawn inside the
    /// same parent. Higher draws in front.
    ///
    /// Order used to be position: shapes were drawn down the list, so moving one
    /// in front of another meant moving it in the file, and a shape could not be
    /// re-stacked without re-authoring the list around it. This is that ordering
    /// said outright.
    ///
    /// Ties keep the order they were authored in, which is what a project
    /// written before z-indexes existed is: every shape at 0, drawn down the
    /// list exactly as before.
    ///
    /// It orders siblings and nothing else. A child is part of its parent's
    /// drawing — it is drawn wherever the parent is drawn — so no z-index on it
    /// can lift it out from behind a shape its parent sits behind.
    public let zIndex: Int

    /// Whether this shape is drawn on a canvas of its own rather than sharing
    /// one with the shapes beside it.
    ///
    /// A canvas is earned rather than asked for by default: a track needs one,
    /// because a shape that moves independently cannot share a vertex buffer
    /// with shapes that do not, and so does a selection, because the border and
    /// handles are fitted to one shape's box. Everything else shares, which is
    /// what keeps a drawing of forty static shapes to one `MTKView`.
    ///
    /// This is that decision made up front instead. A shape asked for on its own
    /// canvas gets one whether or not it has a track — which is what to reach
    /// for when one is coming later, or when a shape has to stay a layer of its
    /// own for anything to be stacked between it and its neighbours.
    ///
    /// Costs a canvas. Read on the shapes an actionable holds directly, for now:
    /// a nested shape is drawn into its parent's vertex buffer, so it has no
    /// canvas of its own to be given.
    public let ownCanvas: Bool

    /// Whether this shape is drawn while the animation it belongs to is waiting
    /// to play, or only once it is playing.
    ///
    /// A shape has always been backdrop: drawn from the moment the view it backs
    /// is on screen, whether or not anything has been triggered. That is what a
    /// halo behind a card wants, and exactly what a shape that is *part* of the
    /// animation — the puff a button gives off when it is pressed — does not: it
    /// sat there in full view for however long the app waited to trigger the
    /// track, and the only way to keep it off screen until then was to author an
    /// opacity of zero into the first keyframe of a track of its own.
    ///
    /// False is that said outright: nothing is drawn until the run is on screen,
    /// and the shape appears with it. True is the backdrop every shape authored
    /// before this was, which is what an absent key reads as.
    ///
    /// Read on the shapes an actionable holds directly. A nested shape is part
    /// of its parent's drawing — drawn into the parent's vertex buffer — so it
    /// appears and disappears with whatever it is drawn inside of.
    public let showsBeforeAnimation: Bool

    /// Which side of the actionable's content this shape is drawn on — see
    /// `InertiaShapePosition`.
    ///
    /// Read on the shapes an actionable holds directly. A nested shape is part
    /// of its parent's drawing and is drawn wherever the parent is, so its own
    /// position says nothing.
    public let position: InertiaShapePosition

    /// Where this shape sits inside whatever holds it: the actionable whose
    /// canvas it is drawn on, or — for a nested shape — the shape it is drawn
    /// inside of.
    ///
    /// A shape's corners are drawn about the origin of the box that holds it, so
    /// every described vector was authored dead centre of its parent and there
    /// was no way to say otherwise: a circle inside a rectangle sat in the
    /// middle of it, and the only thing that could move it was a track. This is
    /// that placement said outright, in the same five properties a track
    /// interpolates — moved, turned, scaled and faded from where it was drawn.
    ///
    /// The translation is a fraction of the parent's own box, the way every
    /// other measurement on a shape is: 0.5 across is half the parent's width,
    /// whatever that comes out as on screen.
    ///
    /// This is placement rather than animation. It is baked into the corners the
    /// renderer is handed — which is what lets a *nested* shape be placed at all,
    /// since a child is drawn into its parent's vertex buffer and has no canvas
    /// of its own to transform — and a track the shape carries plays on top of
    /// it, moving the shape from where this put it.
    ///
    /// Absent is the identity: drawn exactly where its corners say, which is
    /// where every shape authored before this existed was drawn.
    public let transforms: InertiaAnimationValues?

    /// The placement actually applied — `transforms`, with a NaN out of a
    /// hand-edited file falling back to the identity rather than reaching the
    /// geometry.
    var placement: InertiaAnimationValues { (transforms ?? .identity).sanitized }

    /// The corners as authored, when they were authored one by one. A shape
    /// described by `shape` instead has none of its own and is drawn from that
    /// description, which is what `vertices` resolves.
    public let _vertices: [Vertex]?

    /// The ring of corners the renderer draws, however the shape was authored.
    ///
    /// A described vector resolves to its outline carrying the colour it is
    /// filled with — or, for a shape that is only its outline, the colour it is
    /// stroked with, so an unfilled shape still says where it is to everything
    /// that measures a shape by its corners.
    public var vertices: [Vertex] {
        if let _vertices {
            return _vertices
        } else if let shape {
            let color = shape.fill ?? shape.stroke ?? InertiaColor(red: 0, green: 0, blue: 0, alpha: 0)
            return shape.outline.map { Vertex(position: $0, color: color) }
        } else {
            return []
        }
    }

    /// This shape's own track, if it was given one. Read at the same playhead
    /// as everything else in the container, so a shape moves in time with the
    /// animation it was authored beside rather than on a clock of its own.
    public let animation: InertiaAnimationSchema?
    public let shape: InertiaShapeProperties?

    /// The shapes drawn inside this one, in the units of *its* box — 1 is this
    /// shape's shorter side, the way 1 is the view's shorter side one level up.
    ///
    /// A child is part of its parent's drawing rather than a drawing of its own:
    /// it is drawn on the parent's canvas, and every transform that moves the
    /// parent moves it too. That is the whole point of nesting one inside
    /// another — a face drawn inside a head turns when the head does.
    ///
    /// Empty for the shapes that have always existed, and absent from the wire
    /// for them, so a project authored before nesting reads unchanged.
    public let shapes: [InertiaShape]

    /// `_vertices` is written as `vertices`: the corners are what a shape has
    /// always been on the wire, and the leading underscore is only how the
    /// resolved list and the authored one are told apart in here.
    private enum CodingKeys: String, CodingKey {
        case id
        case zIndex
        case position
        case ownCanvas
        case showsBeforeAnimation
        case transforms
        case _vertices = "vertices"
        case animation
        case shape
        case shapes
    }

    public init(
        id: InertiaID,
        shape: InertiaShapeProperties? = nil,
        vertices: [Vertex]?,
        animation: InertiaAnimationSchema? = nil,
        shapes: [InertiaShape] = [],
        zIndex: Int = 0,
        position: InertiaShapePosition = .bottom,
        ownCanvas: Bool = false,
        showsBeforeAnimation: Bool = true,
        transforms: InertiaAnimationValues? = nil
    ) {
        self.id = id
        self.shape = shape
        self._vertices = vertices
        self.animation = animation
        self.shapes = shapes
        self.zIndex = zIndex
        self.position = position
        self.ownCanvas = ownCanvas
        self.showsBeforeAnimation = showsBeforeAnimation
        self.transforms = transforms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(InertiaID.self, forKey: .id)
        _vertices = try container.decodeIfPresent([Vertex].self, forKey: ._vertices)
        animation = try container.decodeIfPresent(InertiaAnimationSchema.self, forKey: .animation)
        shape = try container.decodeIfPresent(InertiaShapeProperties.self, forKey: .shape)
        // Absent is a shape with nothing inside it rather than a malformed one:
        // every shape authored before nesting existed is written without the key.
        shapes = try container.decodeIfPresent([InertiaShape].self, forKey: .shapes) ?? []
        // Absent is the bottom of the stack, which is where every shape authored
        // before z-indexes existed sat: all at 0, drawn in the order they were
        // written down.
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        // Absent is the backdrop a shape has always been.
        position = try container.decodeIfPresent(InertiaShapePosition.self, forKey: .position) ?? .bottom
        // Absent is a shape that shares, which is what every shape authored
        // before this asked for one did.
        ownCanvas = try container.decodeIfPresent(Bool.self, forKey: .ownCanvas) ?? false
        // Absent is the backdrop a shape has always been: drawn whether or not
        // anything is playing.
        showsBeforeAnimation = try container.decodeIfPresent(Bool.self, forKey: .showsBeforeAnimation) ?? true
        // Absent is a shape drawn exactly where its corners say — the identity
        // placement every shape authored before this had.
        transforms = try container.decodeIfPresent(InertiaAnimationValues.self, forKey: .transforms)
    }

    /// The same shape carrying a different track — what the editor writes back
    /// when a gesture on a selected shape is recorded.
    ///
    /// The corners travel across as they were *authored* rather than as they
    /// resolve: a described shape given its animation this way is still a
    /// description, and does not quietly become the ring of corners it happens
    /// to draw as right now.
    public func with(animation: InertiaAnimationSchema?) -> InertiaShape {
        InertiaShape(
            id: id,
            shape: shape,
            vertices: _vertices,
            animation: animation,
            shapes: shapes,
            zIndex: zIndex,
            position: position,
            ownCanvas: ownCanvas,
            showsBeforeAnimation: showsBeforeAnimation,
            transforms: transforms
        )
    }

    /// The same shape with a different list of shapes inside it.
    public func with(shapes: [InertiaShape]) -> InertiaShape {
        InertiaShape(
            id: id,
            shape: shape,
            vertices: _vertices,
            animation: animation,
            shapes: shapes,
            zIndex: zIndex,
            position: position,
            ownCanvas: ownCanvas,
            showsBeforeAnimation: showsBeforeAnimation,
            transforms: transforms
        )
    }

    /// The same shape placed somewhere else in its parent — what the editor
    /// writes back when the viewport is drawing rather than animating, and the
    /// transform tools are offsetting a shape instead of recording a take.
    public func with(transforms: InertiaAnimationValues?) -> InertiaShape {
        InertiaShape(
            id: id,
            shape: shape,
            vertices: _vertices,
            animation: animation,
            shapes: shapes,
            zIndex: zIndex,
            position: position,
            ownCanvas: ownCanvas,
            showsBeforeAnimation: showsBeforeAnimation,
            transforms: transforms
        )
    }

    /// The length a child's coordinates are multiples of: the shorter side of
    /// this shape's own box, in whatever units this shape is itself measured in.
    ///
    /// A described vector says its size outright. One authored corner by corner
    /// does not, so it is measured — the box its own corners occupy, which is
    /// the same thing the description would have named.
    ///
    /// One length rather than two, for the reason the actionable's own unit is
    /// one length — see `InertiaShapesView.unit`. Scaling a child by this box's
    /// width across and its height down would stretch it in whatever direction
    /// the parent happens to be longer in, so a circle nested in a wide
    /// rectangle came out an oval; measured against the shorter side it is the
    /// circle it was described as, wherever it is nested.
    var childUnit: CGFloat {
        if let shape, _vertices == nil {
            return Swift.min(shape.width, shape.height)
        }

        let positions = vertices.map(\.position)
        guard let first = positions.first else { return 0 }

        let minX = positions.reduce(first.x) { Swift.min($0, $1.x) }
        let maxX = positions.reduce(first.x) { Swift.max($0, $1.x) }
        let minY = positions.reduce(first.y) { Swift.min($0, $1.y) }
        let maxY = positions.reduce(first.y) { Swift.max($0, $1.y) }

        return Swift.min(maxX - minX, maxY - minY)
    }

    /// Everything this shape draws, as the one triangle list the renderer takes:
    /// the fill first, then the stroke over it, then whatever is nested inside
    /// it — each child scaled into this shape's box and drawn over it.
    ///
    /// The order is the order they are drawn in — the renderer blends
    /// source-over down the list and keeps no depth — which is what puts the
    /// outline on top of the area it encloses rather than under it, and the
    /// children on top of both. A shape authored corner by corner is all fill,
    /// since a stroke is something a *described* vector carries.
    ///
    /// Everything here comes out placed by `transforms`, children included: a
    /// child is drawn into this buffer rather than onto a canvas of its own, so
    /// baking the placement into the corners is the only place a nested shape
    /// can be moved at all.
    public var triangles: [Vertex] {
        let own = ownTriangles

        guard !shapes.isEmpty else { return placed(own) }

        // A child is measured in this shape's box and centred where this shape
        // is centred, so scaling by that box is the whole of the transform: the
        // origin the two share needs no offset. Where the child asked to sit in
        // that box is already in the corners it hands over.
        //
        // Stacked rather than taken in list order: the renderer blends down the
        // list and keeps no depth, so the order they are handed over in *is*
        // their z-ordering.
        let unit = childUnit
        return placed(own + shapes.stacked.flatMap { child in
            child.triangles.map { vertex in
                Vertex(
                    position: InertiaPoint(
                        x: vertex.position.x * unit,
                        y: vertex.position.y * unit
                    ),
                    color: vertex.color
                )
            }
        })
    }

    /// What this shape draws itself, before anything nested inside it and before
    /// `transforms` places any of it.
    ///
    /// The area the outline encloses and then the outline over it, which is the
    /// order they are drawn in. A shape authored corner by corner is all fill,
    /// since a stroke is something a *described* vector carries.
    ///
    /// Held out of `triangles` because it is also what a press is tested
    /// against: a hit walks down the same tree the drawing is built up, and at
    /// each shape it has to be able to ask what *that* shape covers rather than
    /// what its whole branch does — see `hitTest(_:)`.
    var ownTriangles: [Vertex] {
        if let shape, _vertices == nil {
            return shape.fillTriangles + shape.strokeTriangles
        }

        return fan(vertices)
    }

    /// The shape a press at `point` lands on — this one, or the innermost shape
    /// nested inside it — or nil for a press that misses everything here.
    ///
    /// `point` is in the units this shape is measured in, which is the space its
    /// own `triangles` answer in: the parent's box, before this shape's
    /// placement has moved anything.
    ///
    /// What is tested is the drawing rather than the box around it. A press in
    /// the corner of a circle's bounding box, or in the margin beside a
    /// triangle's slope, misses — so it falls through to whatever is behind
    /// instead of being swallowed by a backdrop the user cannot see there. An
    /// unfilled shape is its outline and nothing more, so a press through the
    /// middle of a ring misses it too.
    ///
    /// Children first and back to front reversed, because that is the order they
    /// are drawn in and a press belongs to whatever is on top of the stack at
    /// that point — the same reading `triangles` lays down and this one inverts.
    func hitTest(_ point: InertiaPoint) -> InertiaShape? {
        guard let local = unplaced(point) else { return nil }

        let unit = childUnit
        if unit > 0 {
            for child in shapes.stacked.reversed() {
                if let hit = child.hitTest(InertiaPoint(x: local.x / unit, y: local.y / unit)) {
                    return hit
                }
            }
        }

        return hits(local, ownTriangles) ? self : nil
    }

    /// `point` carried back out of `transforms` — the inverse of the trip
    /// `placed(_:)` takes a corner on, so a press given in the parent's box
    /// lands in the space this shape's own corners were authored in.
    ///
    /// Nil for a shape scaled to nothing: it draws no area at all, so there is
    /// nothing for a press to land on and no scale to divide back out.
    private func unplaced(_ point: InertiaPoint) -> InertiaPoint? {
        let placement = placement
        guard placement != .identity else { return point }
        guard placement.scale != 0 else { return nil }

        // Turned back rather than forward, and the move undone before the turn,
        // because `placed` moves last.
        let radians = -(placement.rotate + placement.rotateCenter) * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        let x = point.x - placement.translate.width
        let y = point.y - placement.translate.height

        return InertiaPoint(
            x: (x * cosine - y * sine) / placement.scale,
            y: (x * sine + y * cosine) / placement.scale
        )
    }

    /// `vertices` moved to where `transforms` places this shape in its parent.
    ///
    /// Scaled and turned about the origin of the parent's box — which is the
    /// point a described vector's outline is drawn around, so a shape left where
    /// it was authored scales and turns about its own middle — and then moved,
    /// in fractions of that same box.
    ///
    /// Both rotations turn about that one point. `rotate` and `rotateCenter`
    /// differ only in the anchor a view is turned about, and a ring of corners
    /// has no view box to anchor to, so what a shape does with them is the one
    /// rotation their sum describes.
    ///
    /// Opacity is carried in the corners' own alpha, since the fade has to
    /// survive being flattened into a buffer shared with shapes that are not
    /// faded.
    private func placed(_ vertices: [Vertex]) -> [Vertex] {
        let placement = placement
        guard placement != .identity else { return vertices }

        let radians = (placement.rotate + placement.rotateCenter) * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        return vertices.map { vertex in
            let x = vertex.position.x * placement.scale
            let y = vertex.position.y * placement.scale

            return Vertex(
                position: InertiaPoint(
                    x: x * cosine - y * sine + placement.translate.width,
                    y: x * sine + y * cosine + placement.translate.height
                ),
                color: InertiaColor(
                    red: vertex.color.red,
                    green: vertex.color.green,
                    blue: vertex.color.blue,
                    alpha: vertex.color.alpha * Float(placement.opacity)
                )
            )
        }
    }

    /// Every corner this shape's drawing reaches, its children's included, in
    /// the units this shape is measured in.
    ///
    /// What the canvas is fitted to — see `Collection.bounds`. A ring of corners
    /// alone would leave a child hanging over the edge of the canvas its parent
    /// sized, and cut it there.
    /// Placed by `transforms`, the same as the triangles are: the canvas is
    /// fitted to where the drawing ends up, not to where it was drawn.
    var enclosingVertices: [Vertex] {
        let unit = childUnit
        return placed(vertices + shapes.flatMap { child in
            child.enclosingVertices.map { vertex in
                Vertex(
                    position: InertiaPoint(
                        x: vertex.position.x * unit,
                        y: vertex.position.y * unit
                    ),
                    color: vertex.color
                )
            }
        })
    }

    /// Every corner the shape called `shapeId` reaches — this shape itself, or
    /// one nested anywhere inside it — in the units *this* shape is measured in.
    ///
    /// Nil when nothing in here answers to that name.
    ///
    /// A child is drawn in its parent's box and placed by it, so a nested
    /// shape's corners are carried back up through every parent between it and
    /// here: scaled by each one's box on the way, then placed by each one's
    /// transform. That is the same trip `enclosingVertices` takes a whole
    /// drawing on, walked down one branch instead of across all of them, which
    /// is what puts the answer in the space the canvas is fitted to.
    func enclosingVertices(of shapeId: InertiaID) -> [Vertex]? {
        guard id != shapeId else { return enclosingVertices }

        let unit = childUnit

        for child in shapes {
            guard let found = child.enclosingVertices(of: shapeId) else { continue }

            return placed(found.map { vertex in
                Vertex(
                    position: InertiaPoint(
                        x: vertex.position.x * unit,
                        y: vertex.position.y * unit
                    ),
                    color: vertex.color
                )
            })
        }

        return nil
    }

    /// Everything this shape draws, restated against `bounds` — the canvas's own
    /// box — so (0, 0) is the canvas's top-left corner and (1, 1) its
    /// bottom-right, which is the space the renderer draws in.
    ///
    /// Triangles rather than corners, because by this point the shape *is* its
    /// drawing: the fill and the stroke have been resolved into one list, and a
    /// ring of corners could no longer say which of the two it was.
    public func triangles(normalizedTo bounds: CGRect) -> [Vertex] {
        guard bounds.width > 0, bounds.height > 0 else { return triangles }

        return triangles.map { vertex in
            Vertex(
                position: InertiaPoint(
                    x: (vertex.position.x - bounds.minX) / bounds.width,
                    y: (vertex.position.y - bounds.minY) / bounds.height
                ),
                color: vertex.color
            )
        }
    }
}

/// A ring of corners as the triangle list the renderer draws: a fan around the
/// first corner, so three corners are a triangle and four a quad. Fewer than
/// three enclose no area and contribute nothing.
///
/// Every ring a shape resolves to is convex, so the fan covers it exactly from
/// whichever corner it starts at.
func fan(_ vertices: [Vertex]) -> [Vertex] {
    guard vertices.count >= 3 else { return [] }

    return (1..<(vertices.count - 1)).flatMap {
        [vertices[0], vertices[$0], vertices[$0 + 1]]
    }
}

/// Whether `point` falls on any of `triangles`, the list read three corners at a
/// time — the way the renderer draws it, so what answers yes is exactly what was
/// painted.
///
/// A trailing corner or two, which the renderer would not draw either, is left
/// out rather than treated as a triangle of its own.
func hits(_ point: InertiaPoint, _ triangles: [Vertex]) -> Bool {
    stride(from: 0, to: triangles.count - triangles.count % 3, by: 3).contains { index in
        contains(
            point,
            triangles[index].position,
            triangles[index + 1].position,
            triangles[index + 2].position
        )
    }
}

/// Whether `point` is inside the triangle `a`, `b`, `c`.
///
/// Which side of each edge the point falls on, by the sign of the cross product
/// with that edge. Inside is the same side of all three; a zero is the point
/// sitting on an edge, which counts as inside, so two triangles sharing an edge
/// leave no seam for a press to fall through.
///
/// Winding is not assumed: the rings a shape resolves to are wound whichever way
/// they were authored, and a fan of a clockwise ring is every bit as much a
/// triangle as a fan of a counter-clockwise one.
private func contains(_ point: InertiaPoint, _ a: InertiaPoint, _ b: InertiaPoint, _ c: InertiaPoint) -> Bool {
    func side(_ point: InertiaPoint, _ start: InertiaPoint, _ end: InertiaPoint) -> Double {
        (point.x - end.x) * (start.y - end.y) - (start.x - end.x) * (point.y - end.y)
    }

    let ab = side(point, a, b)
    let bc = side(point, b, c)
    let ca = side(point, c, a)

    return !((ab < 0 || bc < 0 || ca < 0) && (ab > 0 || bc > 0 || ca > 0))
}

public extension InertiaShapeProperties {
    /// How many corners a round vector's ring is cut into. An oval has no
    /// corners of its own, so it is drawn as the many-sided polygon that reads
    /// as one at the sizes a shape is authored at — and the same count on every
    /// runtime, so an oval authored once is the same drawing wherever it is
    /// played back.
    static let ovalSegments = 48

    /// The ring of corners a described vector is drawn from, in the actionable's
    /// own units and centred on its top-left corner — the origin the description
    /// is measured from.
    ///
    /// Matches the Kotlin and WebGL runtimes corner for corner, so one authored
    /// vector is the same drawing on all three.
    ///
    /// A square, a circle and a triangle are the descriptions with one
    /// measurement rather than two, so each is sized by the longer side of the
    /// box it was drawn in — the shape stays square, stays round, stays a
    /// triangle whatever box it was dragged out over.
    var outline: [InertiaPoint] {
        let size = max(width, height)

        /// The ring inscribed in a box: one corner per segment, stepping around
        /// the ellipse.
        func ring(_ width: CGFloat, _ height: CGFloat) -> [InertiaPoint] {
            let radiusX = width / 2
            let radiusY = height / 2

            return (0..<Self.ovalSegments).map { segment in
                let angle = 2 * CGFloat.pi * CGFloat(segment) / CGFloat(Self.ovalSegments)
                return InertiaPoint(x: radiusX * cos(angle), y: radiusY * sin(angle))
            }
        }

        /// The four corners of a box, drawn about its centre.
        func quad(_ width: CGFloat, _ height: CGFloat) -> [InertiaPoint] {
            let halfWidth = width / 2
            let halfHeight = height / 2
            return [
                InertiaPoint(x: -halfWidth, y: -halfHeight),
                InertiaPoint(x: halfWidth, y: -halfHeight),
                InertiaPoint(x: halfWidth, y: halfHeight),
                InertiaPoint(x: -halfWidth, y: halfHeight)
            ]
        }

        switch type {
        case .rectangle:
            return quad(width, height)
        case .square:
            return quad(size, size)
        case .circle:
            return ring(size, size)
        case .oval:
            return ring(width, height)
        case .triangle:
            // An isosceles triangle with mirror symmetry about the y-axis.
            let triangleHeight = size * sqrt(3) / 2
            let halfBase = size / 2
            return [
                InertiaPoint(x: 0, y: triangleHeight / 2),
                InertiaPoint(x: -halfBase, y: -triangleHeight / 2),
                InertiaPoint(x: halfBase, y: -triangleHeight / 2)
            ]
        }
    }

    /// The area the outline encloses, as triangles. Empty for a shape with no
    /// fill, which is an outline drawn on nothing.
    var fillTriangles: [Vertex] {
        guard let fill else { return [] }

        return fan(outline.map { Vertex(position: $0, color: fill) })
    }

    /// The outline itself, as triangles: the band between the ring and the same
    /// ring inset by `strokeWidth`.
    ///
    /// Inset rather than centred or outset, so a stroke stays inside the box the
    /// shape was authored at — see `strokeWidth`. Each corner is mitred, so the
    /// band turns a corner in one piece rather than leaving the wedge that
    /// offsetting each edge on its own would.
    ///
    /// Empty unless the shape was given both a colour and a width to draw the
    /// outline with.
    var strokeTriangles: [Vertex] {
        guard let stroke, strokeWidth > 0 else { return [] }

        let outline = outline
        guard outline.count >= 3 else { return [] }

        // A stroke thicker than the shape has room for would turn the inner ring
        // inside out. Held at the point where the ring closes on itself, which
        // is a shape drawn solid in the stroke's colour.
        let inset = min(strokeWidth, min(width, height) / 2)
        let inner = outline.inset(by: inset)

        return (0..<outline.count).flatMap { index -> [Vertex] in
            let next = (index + 1) % outline.count
            let corner = { (point: InertiaPoint) in Vertex(position: point, color: stroke) }

            return [
                corner(outline[index]), corner(outline[next]), corner(inner[next]),
                corner(outline[index]), corner(inner[next]), corner(inner[index])
            ]
        }
    }
}

private extension Array where Element == InertiaPoint {
    /// The same ring moved `distance` towards its own inside, corner by corner.
    ///
    /// Each corner travels along the bisector of the two edges meeting at it,
    /// far enough that both edges end up exactly `distance` in — which is what
    /// makes the band an even thickness all the way round instead of thinning at
    /// the corners. Very sharp corners want to travel a very long way, so the
    /// distance is capped; the ring is convex and the cap only ever pulls a
    /// spike back in.
    ///
    /// Which way "inside" is depends on which way the ring was wound, so that is
    /// measured rather than assumed: the sign of the area it encloses.
    func inset(by distance: CGFloat) -> [InertiaPoint] {
        let winding: CGFloat = signedArea < 0 ? -1 : 1

        return indices.map { index in
            let previous = self[(index - 1 + count) % count]
            let corner = self[index]
            let next = self[(index + 1) % count]

            // The inward normal of each edge meeting at this corner.
            let incoming = normal(from: previous, to: corner, winding: winding)
            let outgoing = normal(from: corner, to: next, winding: winding)

            let bisector = normalized(InertiaPoint(
                x: incoming.x + outgoing.x,
                y: incoming.y + outgoing.y
            ))

            // How far along the bisector puts both edges `distance` in. Zero
            // when the two edges double back on each other, which is a corner
            // with no inside to move towards.
            let projection = bisector.x * outgoing.x + bisector.y * outgoing.y
            guard projection > 0.1 else { return corner }

            let travel = distance / projection
            return InertiaPoint(x: corner.x + bisector.x * travel, y: corner.y + bisector.y * travel)
        }
    }

    /// Twice the area the ring encloses, signed by the direction it is wound in.
    /// Only the sign is read.
    var signedArea: CGFloat {
        indices.reduce(0) { total, index in
            let corner = self[index]
            let next = self[(index + 1) % count]
            return total + (corner.x * next.y - next.x * corner.y)
        }
    }

    /// The unit normal of an edge, pointing at the ring's inside.
    func normal(from start: InertiaPoint, to end: InertiaPoint, winding: CGFloat) -> InertiaPoint {
        let edge = InertiaPoint(x: end.x - start.x, y: end.y - start.y)
        return normalized(InertiaPoint(x: -edge.y * winding, y: edge.x * winding))
    }

    func normalized(_ point: InertiaPoint) -> InertiaPoint {
        let length = sqrt(point.x * point.x + point.y * point.y)
        guard length > 0 else { return InertiaPoint(x: 0, y: 0) }
        return InertiaPoint(x: point.x / length, y: point.y / length)
    }
}

public extension Collection where Element == InertiaShape {
    /// These shapes back to front: the order they are drawn in, which is what
    /// their z-indexes say — see `InertiaShape.zIndex`.
    ///
    /// Ties keep the order they were authored in. Swift's sort is not itself
    /// stable, so the authored position is sorted on as well rather than
    /// trusted to survive — which is what keeps a project with no z-indexes in
    /// it drawing exactly as it did when the list *was* the ordering.
    var stacked: [InertiaShape] {
        enumerated()
            .sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
            .map(\.element)
    }

    /// The smallest box holding every corner of these shapes, in the units they
    /// are authored in — multiples of the actionable's shorter side, so a box
    /// 1 wide is as wide as that side and one 3 wide three times it.
    ///
    /// This is what the canvas is sized and placed by. Sizing it to the shapes
    /// rather than to the container is what keeps a shape whole: a canvas is a
    /// rectangle that rotates with the view it backs, so anything reaching past
    /// its edge is cut — and a canvas fitted to the container was already
    /// cutting a shape bigger than the container, then sweeping that straight
    /// edge through the artwork as the view turned. Fitted to the shapes, there
    /// is nothing outside it to lose.
    ///
    /// Nil when the shapes enclose no area, which is also when there is nothing
    /// to draw.
    var bounds: CGRect? {
        boundingBox(around: flatMap { $0.enclosingVertices.map(\.position) })
    }

    /// The shape a press at `point` lands on, wherever it is nested, or nil for
    /// a press that misses every one of them.
    ///
    /// `point` is in the units these shapes are authored in — multiples of the
    /// actionable's shorter side, measured from its middle, which is the same
    /// space `bounds` answers in.
    ///
    /// Front to back, so a press on two overlapping shapes picks the one drawn
    /// on top: the list is stacked and then read backwards, which is the drawing
    /// order reversed. What each shape is tested against is its drawing rather
    /// than its box — see `InertiaShape.hitTest(_:)`.
    func hitTest(_ point: InertiaPoint) -> InertiaShape? {
        for shape in stacked.reversed() {
            if let hit = shape.hitTest(point) { return hit }
        }

        return nil
    }

    /// The box one shape in here occupies, wherever it is nested, in the units
    /// these shapes are authored in.
    ///
    /// The same space `bounds` answers in, so the two can be placed against one
    /// another on a canvas — which is what the editor draws a selection's border
    /// from: the border belongs to one shape while the canvas is fitted to the
    /// whole drawing.
    ///
    /// Looks *inside* these shapes as well as at them, because a nested shape is
    /// a row of its own in the editor's hierarchy and can be picked there even
    /// though it has no canvas of its own.
    ///
    /// Nil when no shape in here answers to that name, and nil when the one that
    /// does encloses no area — a border around nothing is nothing to draw.
    func bounds(of shapeId: InertiaID) -> CGRect? {
        for shape in self {
            guard let vertices = shape.enclosingVertices(of: shapeId) else { continue }

            return boundingBox(around: vertices.map(\.position))
        }

        return nil
    }

    /// What one unit of the box the shape called `shapeId` is *placed* in is
    /// worth here — in the units these shapes are authored in.
    ///
    /// A placement is measured in the box the shape sits in rather than in the
    /// units the drawing around it is measured in, and those are only the same
    /// thing for a shape on the canvas itself, which is placed in the
    /// actionable's own box. A nested one is placed in its parent's, and its
    /// parent may be nested in turn — so the answer is every `childUnit` between
    /// here and it, multiplied together, which is exactly the scaling
    /// `InertiaShape.triangles` walks a child's corners back up through.
    ///
    /// 1 for a shape on the canvas itself, and nil when nothing in here answers
    /// to that name.
    ///
    /// What it is for: the editor's canvas turns a drag in points into a
    /// placement, and a nested shape's placement is in a smaller unit than the
    /// drawing it is part of — see `ShapeCanvasView`.
    func placementUnit(of shapeId: InertiaID) -> CGFloat? {
        for shape in self {
            if shape.id == shapeId { return 1 }

            guard let nested = shape.shapes.placementUnit(of: shapeId) else { continue }

            return shape.childUnit * nested
        }

        return nil
    }
}

/// The smallest rect holding every one of `positions`, or nil when they enclose
/// no area.
///
/// Shared by the two ways a drawing is asked for a box — every shape on a
/// canvas, and one shape out of it — so the two are measured identically.
///
/// Nil for a box that is not a finite rect, too. A canvas is sized by this box
/// and placed by its middle, and the middle of an unbounded box is `-∞ + ∞` — a
/// NaN, which traps the moment it reaches a geometry modifier. One coordinate
/// out of a hand-edited file is enough to produce one, so it is rejected here
/// rather than in each of the places that measure against it.
private func boundingBox(around positions: [InertiaPoint]) -> CGRect? {
    guard let first = positions.first else { return nil }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for position in positions {
        minX = Swift.min(minX, position.x)
        maxX = Swift.max(maxX, position.x)
        minY = Swift.min(minY, position.y)
        maxY = Swift.max(maxY, position.y)
    }

    let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    guard bounds.width > 0, bounds.height > 0,
          minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite
    else { return nil }

    return bounds
}
