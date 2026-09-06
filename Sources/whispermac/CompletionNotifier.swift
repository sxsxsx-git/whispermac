import Foundation
import UserNotifications

/// Abstraction over UNUserNotificationCenter so completion notifications can be
/// tested with a spy; the system-backed implementation is the production default.
protocol NotificationPosting: Sendable {
    /// Requests `.alert` authorization; returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Posts a local notification; delivery failures are silent.
    func post(title: String, body: String) async
}

/// Real `UNUserNotificationCenter`-backed poster.
struct SystemNotificationPoster: NotificationPosting {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])) ?? false
    }

    func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "whispermac.batch-finished-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        _ = try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Posts a best-effort local notification when a transcription batch finishes.
///
/// Authorization (`.alert` only) is requested lazily on the first transcription
/// start — never at app launch — and only once, remembered in UserDefaults.
/// Everything is inert when the process has no bundle identifier (bare
/// `swift run`/`swift test`), where `UNUserNotificationCenter.current()` would
/// otherwise throw.
@MainActor
final class CompletionNotifier {
    static let authorizationAskedDefaultsKey = "hasRequestedNotificationAuthorization"

    private let poster: NotificationPosting
    private let defaults: UserDefaults
    private let isEligibleForNotifications: @Sendable () -> Bool

    init(
        poster: NotificationPosting = SystemNotificationPoster(),
        defaults: UserDefaults = .standard,
        isEligibleForNotifications: @escaping @Sendable () -> Bool = { Bundle.main.bundleIdentifier != nil }
    ) {
        self.poster = poster
        self.defaults = defaults
        self.isEligibleForNotifications = isEligibleForNotifications
    }

    /// Called when a transcription run starts. The authorization request runs in
    /// the background so a user staring at the permission dialog never delays the
    /// batch; the "asked" flag is set synchronously first to prevent double asks.
    func prepareForRun() async {
        guard isEligibleForNotifications() else { return }
        guard !defaults.bool(forKey: Self.authorizationAskedDefaultsKey) else { return }
        defaults.set(true, forKey: Self.authorizationAskedDefaultsKey)
        _ = await poster.requestAuthorization()
    }

    /// Notifies that a batch finished. Cancelled batches stay silent; posting is
    /// best-effort and silently does nothing when notifications are unavailable.
    func notifyBatchFinished(successCount: Int, failureCount: Int, wasCancelled: Bool = false) async {
        guard !wasCancelled else { return }
        guard isEligibleForNotifications() else { return }
        if failureCount == 0 {
            await poster.post(
                title: L.tr("notification.title.success"),
                body: L.tr("notification.body.success", successCount)
            )
        } else {
            await poster.post(
                title: L.tr("notification.title.failed"),
                body: L.tr("notification.body.failed", failureCount)
            )
        }
    }
}
