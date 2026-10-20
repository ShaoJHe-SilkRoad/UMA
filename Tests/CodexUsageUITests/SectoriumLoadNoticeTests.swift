import Testing
import HESectoriumCore
@testable import CodexUsageUI

@Suite("Sectorium Load failure notices")
struct SectoriumLoadNoticeTests {
    @Test func nativeRefusalRemainsVisible() {
        let result = OperationResult(operationID: "fixture", mode: .manual, steps: [],
            failure: .workbenchFailed("Load failed: Operation not permitted"))
        let notice = SectoriumUserNotice.operation(result, observed: false)
        #expect(notice.english.contains("Operation not permitted"))
        #expect(notice.chinese.contains("加载未完成"))
    }
    @Test func cancelledAuthorizationInvitesDeliberateRetry() {
        let result = OperationResult(operationID: "fixture", mode: .manual, steps: [],
            failure: .workbenchFailed("Load failed: User cancelled authorization"))
        let notice = SectoriumUserNotice.operation(result, observed: false)
        #expect(notice.english == "Load was cancelled. Select Load to try again.")
        #expect(notice.chinese.contains("重试"))
    }
}
