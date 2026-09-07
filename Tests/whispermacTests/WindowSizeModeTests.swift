import Foundation
import Testing
@testable import whispermac

/// Pure-conversion coverage for the responsive width classes: the workspace
/// enters `expanded` only past the expand threshold, leaves only below the
/// lower collapse threshold, and the band in between is stable (hysteresis),
/// so a live resize cannot oscillate the layout. Invalid measurements are
/// ignored and keep the current state.
struct WindowSizeModeTests {

    private static let expand = TaskWorkspaceMetrics.expandWorkspaceThreshold
    private static let collapse = TaskWorkspaceMetrics.collapseWorkspaceThreshold

    // MARK: initialization

    @Test
    func uninitializedResolvesFromFirstValidWidth() {
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: 743) == .regular)
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: 1203) == .expanded)
    }

    @Test
    func uninitializedInvalidMeasurementsStayRegularDefault() {
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: 0) == .regular)
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: -40) == .regular)
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: .infinity) == .regular)
        #expect(WindowSizeMode.next(current: nil, workspaceWidth: .nan) == .regular)
    }

    @Test
    func invalidMeasurementsKeepCurrentState() {
        #expect(WindowSizeMode.next(current: .expanded, workspaceWidth: 0) == .expanded)
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: .nan) == .regular)
    }

    // MARK: anchors

    @Test
    func minimumWindowStaysRegular() {
        // 980 window - 236 queue - 1 divider = 743 workspace.
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: 743) == .regular)
    }

    @Test
    func typicalLargeWindowExpands() {
        // 1440 window - 237 = 1203 workspace.
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: 1203) == .expanded)
    }

    // MARK: thresholds

    @Test
    func expandThresholdIsInclusive() {
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: Self.expand) == .expanded)
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: Self.expand - 1) == .regular)
    }

    @Test
    func collapseThresholdIsExclusive() {
        #expect(WindowSizeMode.next(current: .expanded, workspaceWidth: Self.collapse) == .expanded)
        #expect(WindowSizeMode.next(current: .expanded, workspaceWidth: Self.collapse - 1) == .regular)
    }

    // MARK: hysteresis band

    @Test
    func sameWidthResolvesDifferentlyDependingOnCurrentState() {
        let inBand = (Self.expand + Self.collapse) / 2
        #expect(Self.expand - Self.collapse == 40)
        #expect(WindowSizeMode.next(current: .regular, workspaceWidth: inBand) == .regular)
        #expect(WindowSizeMode.next(current: .expanded, workspaceWidth: inBand) == .expanded)
    }

    @Test
    func expandedSurvivesFullBandAndOnlyCollapsesBelow() {
        for width in stride(from: Self.collapse, through: Self.expand, by: 10) {
            #expect(WindowSizeMode.next(current: .expanded, workspaceWidth: width) == .expanded)
        }
    }

    // MARK: bidirectional live-resize sequence (plan R1 acceptance)

    @Test
    func bidirectionalThresholdSequence() {
        // 1059 → 1100 → 1080 → 1060 → 1059 from regular must yield
        // regular → expanded → expanded → expanded → regular.
        var current: WindowSizeMode? = .regular
        let widths: [CGFloat] = [1059, 1100, 1080, 1060, 1059]
        let expected: [WindowSizeMode] = [.regular, .expanded, .expanded, .expanded, .regular]
        for (width, want) in zip(widths, expected) {
            current = WindowSizeMode.next(current: current, workspaceWidth: width)
            #expect(current == want)
        }
    }
}
