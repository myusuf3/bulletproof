import Foundation
import Testing
import UserNotifications
@testable import bulletproof

private final class FakeNotificationCenter: NotificationCenterFacade, @unchecked Sendable {
    var status: UNAuthorizationStatus
    var grantOnRequest = false
    private(set) var requestCount = 0
    private(set) var delivered: [(title: String, body: String)] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async -> Bool {
        requestCount += 1
        return grantOnRequest
    }
    func deliver(title: String, body: String) async {
        delivered.append((title, body))
    }
}

struct UserNotifierTests {
    @Test func authorizedDeliversWithoutReRequesting() async {
        let center = FakeNotificationCenter(status: .authorized)
        await UserNotifier.deliver(title: "T", body: "B", via: center)
        #expect(center.delivered.count == 1)
        #expect(center.requestCount == 0)
    }

    @Test func deniedDropsWithoutRequestingAgain() async {
        let center = FakeNotificationCenter(status: .denied)
        await UserNotifier.deliver(title: "T", body: "B", via: center)
        #expect(center.delivered.isEmpty)
        #expect(center.requestCount == 0)
    }

    @Test func undeterminedRequestsOnceThenDeliversIfGranted() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        center.grantOnRequest = true
        await UserNotifier.deliver(title: "T", body: "B", via: center)
        #expect(center.requestCount == 1)
        #expect(center.delivered.count == 1)
    }

    @Test func undeterminedAndRefusedDeliversNothing() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        center.grantOnRequest = false
        await UserNotifier.deliver(title: "T", body: "B", via: center)
        #expect(center.delivered.isEmpty)
    }
}
