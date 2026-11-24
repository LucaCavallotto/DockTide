import CoreGraphics
import DockTideCore

final class OverlapTests {
    let dock = CGRect(x: 400, y: 850, width: 600, height: 50)

    func testEmptyDesktopAndEdgeContactRemainVisible() {
        expectFalse(Overlap.requiresHiding(dock: dock, windows: []))
        expectFalse(Overlap.requiresHiding(dock: dock, windows: [CGRect(x: 400, y: 0, width: 600, height: 850)]))
    }

    func testOverlapIncludesBackgroundWindows() {
        expectTrue(Overlap.requiresHiding(dock: dock, windows: [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 450, y: 200, width: 400, height: 700)
        ]))
    }

    func testAdjacentWindowAndSmallRoundingErrorsDoNotHide() {
        expectFalse(Overlap.requiresHiding(dock: dock, windows: [CGRect(x: 0, y: 0, width: 399, height: 900)]))
        expectFalse(Overlap.requiresHiding(dock: dock, windows: [CGRect(x: 400, y: 0, width: 600, height: 851)]))
    }

    func testInvalidDockDoesNotHide() {
        expectFalse(Overlap.requiresHiding(dock: .zero, windows: [CGRect(x: 0, y: 0, width: 2000, height: 2000)]))
    }
}

func expectFalse(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!condition, "Expected false", file: file, line: line)
}
func expectTrue(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Expected true", file: file, line: line)
}

@main
struct Checks {
    static func main() {
        let tests = OverlapTests()
        tests.testEmptyDesktopAndEdgeContactRemainVisible()
        tests.testOverlapIncludesBackgroundWindows()
        tests.testAdjacentWindowAndSmallRoundingErrorsDoNotHide()
        tests.testInvalidDockDoesNotHide()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let work = CGRect(x: 0, y: 25, width: 1440, height: 805)
        let expanded = FillExpansion.target(window: work, workArea: work, screen: screen)
        expectTrue(expanded == CGRect(x: 0, y: 25, width: 1440, height: 875))
        expectTrue(FillExpansion.target(window: work.insetBy(dx: 8, dy: 8), workArea: work, screen: screen)
                   == CGRect(x: 8, y: 33, width: 1424, height: 859))
        expectTrue(FillExpansion.target(window: CGRect(x: 0, y: 25, width: 720, height: 805), workArea: work, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: CGRect(x: 100, y: 100, width: 900, height: 700), workArea: work, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: work, workArea: screen, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: CGRect(x: 0, y: 0, width: 1440, height: 830), workArea: work, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: work.insetBy(dx: 30, dy: 30), workArea: work, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: screen, workArea: work, screen: screen) == nil)
        // Top-edge dragging may hide the Dock before the final tiled size is reported.
        let noDock = CGRect(x: 0, y: 25, width: 1440, height: 875)
        expectTrue(FillExpansion.target(window: work, liveWorkArea: noDock, reservedWorkArea: work, screen: screen) == expanded)
        expectTrue(FillExpansion.target(window: work.insetBy(dx: 8, dy: 8), liveWorkArea: noDock, reservedWorkArea: work, screen: screen)
                   == CGRect(x: 8, y: 33, width: 1424, height: 859))
        expectTrue(FillExpansion.target(window: noDock, liveWorkArea: noDock, reservedWorkArea: work, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: work, liveWorkArea: noDock, reservedWorkArea: nil, screen: screen) == nil)
        expectTrue(FillExpansion.target(window: CGRect(x: 0, y: 25, width: 720, height: 805), liveWorkArea: noDock, reservedWorkArea: work, screen: screen) == nil)
        var buffer = DiagnosticBuffer(capacity: 3)
        buffer.append("one")
        buffer.append("two")
        buffer.append("three")
        buffer.append("four")
        expectTrue(buffer.entries == ["two", "three", "four"])
        buffer.append("four")
        expectTrue(buffer.entries.count == 3)
        var minimumBuffer = DiagnosticBuffer(capacity: 0)
        minimumBuffer.append("one")
        minimumBuffer.append("two")
        expectTrue(minimumBuffer.entries == ["two"])
        print("Passed 4 overlap, 13 Fill expansion and 3 diagnostic buffer checks.")
    }
}
