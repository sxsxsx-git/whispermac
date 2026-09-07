import SwiftUI

/// Responsive width class of the main workspace, derived from layout
/// geometry — never stored in `AppModel` or persisted settings: the geometry
/// callback converts, and only a changed class writes view-local state.
///
/// `regular` keeps the P0 layout (760 pt left-aligned reading column);
/// `expanded` widens and centers it. The threshold pair carries hysteresis
/// (see `TaskWorkspaceMetrics`) so a live resize never oscillates around a
/// single value. Before the first valid measurement the UI renders `regular`.
enum WindowSizeMode: Equatable {
    case regular
    case expanded

    /// Pure conversion so the hysteresis band is unit-testable. The input is
    /// the actual workspace container width (not the window width minus a
    /// hardcoded queue); non-finite or non-positive widths are ignored and
    /// keep the current state. `nil` means "no valid measurement yet".
    static func next(
        current: WindowSizeMode?,
        workspaceWidth: CGFloat
    ) -> WindowSizeMode {
        guard workspaceWidth.isFinite, workspaceWidth > 0 else {
            return current ?? .regular
        }
        switch current {
        case .expanded:
            return workspaceWidth < TaskWorkspaceMetrics.collapseWorkspaceThreshold
                ? .regular
                : .expanded
        case .regular, .none:
            return workspaceWidth >= TaskWorkspaceMetrics.expandWorkspaceThreshold
                ? .expanded
                : .regular
        }
    }
}

private struct WindowSizeModeKey: EnvironmentKey {
    static let defaultValue: WindowSizeMode = .regular
}

extension EnvironmentValues {
    var windowSizeMode: WindowSizeMode {
        get { self[WindowSizeModeKey.self] }
        set { self[WindowSizeModeKey.self] = newValue }
    }
}
