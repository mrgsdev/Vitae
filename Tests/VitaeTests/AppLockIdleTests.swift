import Foundation
import Testing
@testable import Vitae

/// «Блокировать после бездействия»: время считается от последнего нажатия клавиши или мыши,
/// а не только пока Vitae в фоне. Иначе активное окно Vitae не блокировалось никогда —
/// даже при заблокированном экране или после сна Mac.
@Suite("Блокировка по бездействию") @MainActor
struct AppLockIdleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func manager(enabled: Bool = true, timeout: TimeInterval = 300) -> AppLockManager {
        AppLockManager(isEnabled: { enabled }, timeout: { timeout })
    }

    @Test func activeWindowLocksAfterTimeoutWithoutInput() {
        let lock = manager()
        lock.recordActivity(at: start)
        lock.lockIfIdle(now: start.addingTimeInterval(299))
        #expect(!lock.isLocked)
        lock.lockIfIdle(now: start.addingTimeInterval(300))
        #expect(lock.isLocked, "Vitae осталась активной, но бездействие дольше таймаута")
    }

    @Test func inputPostponesLock() {
        let lock = manager()
        lock.recordActivity(at: start)
        lock.recordActivity(at: start.addingTimeInterval(200))
        lock.lockIfIdle(now: start.addingTimeInterval(450))
        #expect(!lock.isLocked)
        lock.lockIfIdle(now: start.addingTimeInterval(500))
        #expect(lock.isLocked)
    }

    @Test func timeInBackgroundCountsAsIdle() {
        let lock = manager()
        lock.applicationDidResignActive(at: start)
        lock.applicationDidBecomeActive(at: start.addingTimeInterval(120))
        #expect(!lock.isLocked, "вернулись раньше таймаута")
        lock.applicationDidResignActive(at: start.addingTimeInterval(130))
        lock.applicationDidBecomeActive(at: start.addingTimeInterval(431))
        #expect(lock.isLocked)
    }

    @Test func disabledLockNeverLocks() {
        let lock = manager(enabled: false)
        lock.recordActivity(at: start)
        lock.lockIfIdle(now: start.addingTimeInterval(10_000))
        lock.applicationDidResignActive(at: start)
        lock.applicationDidBecomeActive(at: start.addingTimeInterval(10_000))
        #expect(!lock.isLocked)
    }
}
