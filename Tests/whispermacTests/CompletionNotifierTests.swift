import Foundation
import Testing
@testable import whispermac

private struct PostedNotification: Equatable, Sendable {
    let title: String
    let body: String
}

private actor NotificationPosterSpy: NotificationPosting {
    private(set) var requestAuthorizationCount = 0
    private(set) var posted: [PostedNotification] = []
    private let authorizationResult: Bool

    init(authorizationResult: Bool = true) {
        self.authorizationResult = authorizationResult
    }

    func requestAuthorization() async -> Bool {
        requestAuthorizationCount += 1
        return authorizationResult
    }

    func post(title: String, body: String) async {
        posted.append(PostedNotification(title: title, body: body))
    }
}

/// Fresh, isolated defaults so the "asked once" flag never leaks between tests.
private func makeDefaults() -> UserDefaults {
    let suiteName = "CompletionNotifierTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Suite
@MainActor
struct CompletionNotifierTests {
    @Test
    func authorizationIsRequestedOncePerDefaultsFlag() async {
        let spy = NotificationPosterSpy()
        let defaults = makeDefaults()
        let notifier = CompletionNotifier(
            poster: spy,
            defaults: defaults,
            isEligibleForNotifications: { true }
        )

        await notifier.prepareForRun()
        await notifier.prepareForRun()

        #expect(await spy.requestAuthorizationCount == 1)
        #expect(defaults.bool(forKey: CompletionNotifier.authorizationAskedDefaultsKey))
    }

    @Test
    func successfulBatchPostsSuccessNotification() async {
        let spy = NotificationPosterSpy()
        let notifier = CompletionNotifier(
            poster: spy,
            defaults: makeDefaults(),
            isEligibleForNotifications: { true }
        )

        await notifier.notifyBatchFinished(successCount: 3, failureCount: 0)

        let posted = await spy.posted
        #expect(posted.count == 1)
        #expect(posted[0].title == L.tr("notification.title.success"))
        #expect(posted[0].body == L.tr("notification.body.success", 3))
    }

    @Test
    func failedBatchPostsFailureNotification() async {
        let spy = NotificationPosterSpy()
        let notifier = CompletionNotifier(
            poster: spy,
            defaults: makeDefaults(),
            isEligibleForNotifications: { true }
        )

        await notifier.notifyBatchFinished(successCount: 1, failureCount: 2)

        let posted = await spy.posted
        #expect(posted.count == 1)
        #expect(posted[0].title == L.tr("notification.title.failed"))
        #expect(posted[0].body == L.tr("notification.body.failed", 2))
    }

    @Test
    func cancelledBatchPostsNothing() async {
        let spy = NotificationPosterSpy()
        let notifier = CompletionNotifier(
            poster: spy,
            defaults: makeDefaults(),
            isEligibleForNotifications: { true }
        )

        await notifier.notifyBatchFinished(successCount: 2, failureCount: 0, wasCancelled: true)

        #expect(await spy.posted.isEmpty)
    }

    @Test
    func deniedAuthorizationStillPostsBestEffort() async {
        let spy = NotificationPosterSpy(authorizationResult: false)
        let notifier = CompletionNotifier(
            poster: spy,
            defaults: makeDefaults(),
            isEligibleForNotifications: { true }
        )

        await notifier.prepareForRun()
        await notifier.notifyBatchFinished(successCount: 1, failureCount: 0)

        #expect(await spy.requestAuthorizationCount == 1)
        #expect(await spy.posted.count == 1)
    }

    @Test(arguments: ["en", "zh-hans", "ja"])
    func notificationKeysResolveInEveryLocalization(identifier: String) throws {
        let path = try #require(Bundle.module.path(forResource: identifier, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))

        for key in [
            "notification.title.success",
            "notification.body.success",
            "notification.title.failed",
            "notification.body.failed",
        ] {
            let value = bundle.localizedString(forKey: key, value: "", table: "Localizable")
            #expect(!value.isEmpty, "\(key) is empty in \(identifier)")
            #expect(value != key, "\(key) is missing from \(identifier)")
        }
    }

    @Test
    func inertWithoutBundleIdentifier() async {
        // `swift test` runs from an xctest bundle with no Info.plist, so
        // Bundle.main.bundleIdentifier is nil and the notification path must be
        // completely inert: no authorization request, no post, no flag side effect.
        #expect(Bundle.main.bundleIdentifier == nil)

        let spy = NotificationPosterSpy()
        let defaults = makeDefaults()
        let notifier = CompletionNotifier(poster: spy, defaults: defaults)

        await notifier.prepareForRun()
        await notifier.notifyBatchFinished(successCount: 1, failureCount: 0)

        #expect(await spy.requestAuthorizationCount == 0)
        #expect(await spy.posted.isEmpty)
        #expect(!defaults.bool(forKey: CompletionNotifier.authorizationAskedDefaultsKey))
    }
}
