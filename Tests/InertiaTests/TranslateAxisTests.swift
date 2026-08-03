import XCTest
@testable import Inertia

/// The move tool's two axis arrows: where they sit next to a node, which one a
/// press picks, and what a drag on one is allowed to author.
///
/// The geometry is shared by the chrome that draws the arrows and the gesture
/// that runs them, and it is the same arithmetic in all three runtimes — a press
/// 22 points past the drawn edge of the box has to find an arrow on every one of
/// them.
final class TranslateAxisTests: XCTestCase {
    private let center = CGPoint(x: 200, y: 100)
    private let drawnSize = CGSize(width: 80, height: 40)

    /// The distance from the drawn edge of the box to the middle of an arrow: the
    /// gap, plus half of the head that starts where the gap ends.
    private var reach: CGFloat {
        InertiaTranslateAxes.gap + InertiaTranslateAxes.length / 2
    }

    func testArrowsSitOffTheEdgeTheyPointThrough() {
        XCTAssertEqual(
            InertiaTranslateAxes.center(.horizontal, drawnCenter: center, drawnSize: drawnSize),
            CGPoint(x: center.x + drawnSize.width / 2 + reach, y: center.y)
        )
        XCTAssertEqual(
            InertiaTranslateAxes.center(.vertical, drawnCenter: center, drawnSize: drawnSize),
            CGPoint(x: center.x, y: center.y - drawnSize.height / 2 - reach)
        )
    }

    /// A node the schema has scaled up carries its arrows out with it, so the
    /// press that grabbed one before is not the press that grabs it now.
    func testArrowsFollowTheDrawnBoxRatherThanTheLaidOutOne() {
        let scaled = CGSize(width: drawnSize.width * 2, height: drawnSize.height * 2)
        let at = InertiaTranslateAxes.center(.horizontal, drawnCenter: center, drawnSize: scaled)

        XCTAssertEqual(at.x, center.x + drawnSize.width + reach)
        XCTAssertEqual(
            InertiaTranslateAxes.axis(at: at, drawnCenter: center, drawnSize: scaled),
            .horizontal
        )
        XCTAssertNil(InertiaTranslateAxes.axis(at: at, drawnCenter: center, drawnSize: drawnSize))
    }

    func testAPressOnAnArrowPicksItsAxis() {
        for axis in InertiaTranslateAxis.allCases {
            let middle = InertiaTranslateAxes.center(axis, drawnCenter: center, drawnSize: drawnSize)
            XCTAssertEqual(
                InertiaTranslateAxes.axis(at: middle, drawnCenter: center, drawnSize: drawnSize),
                axis
            )
        }
    }

    /// The body of the node is a free move, which is what `nil` stands for — and
    /// so is anywhere else nothing has been drawn.
    func testAPressOffTheArrowsPicksNoAxis() {
        XCTAssertNil(InertiaTranslateAxes.axis(at: center, drawnCenter: center, drawnSize: drawnSize))

        let far = CGPoint(
            x: center.x + drawnSize.width / 2 + reach + InertiaTranslateAxes.touchRadius + 1,
            y: center.y
        )
        XCTAssertNil(InertiaTranslateAxes.axis(at: far, drawnCenter: center, drawnSize: drawnSize))
    }

    func testAnAxisAuthorsOnlyItsOwnComponent() {
        let drag = CGSize(width: 30, height: -12)

        XCTAssertEqual(InertiaTranslateAxis.horizontal.constrain(drag), CGSize(width: 30, height: 0))
        XCTAssertEqual(InertiaTranslateAxis.vertical.constrain(drag), CGSize(width: 0, height: -12))
    }

    /// What the constrained drag becomes once it is folded into a transform: a
    /// fraction of the container, and only along the one axis.
    func testAConstrainedDragMovesTheNodeAlongOneAxisOnly() {
        let container = CGSize(width: 400, height: 200)
        let edit = InertiaToolEdit(translate: InertiaTranslateAxis.horizontal.constrain(CGSize(width: 40, height: 90)))
        let values = InertiaAnimationValues.identity.applying(edit, containerSize: container)

        XCTAssertEqual(values.translate.width, 0.1, accuracy: 0.0001)
        XCTAssertEqual(values.translate.height, 0)
    }
}
