import Foundation
import XCTest
@testable import ZHANARCourseAccess

final class CourseAccessPolicyTests: XCTestCase {
    func testEntitlementRequiresVerifiedProductAndMatchingAccountToken() {
        let learnerID = UUID()

        XCTAssertTrue(CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: true,
            entitlementAccountToken: learnerID,
            currentAccountID: learnerID
        ))
        XCTAssertFalse(CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: false,
            entitlementAccountToken: learnerID,
            currentAccountID: learnerID
        ))
        XCTAssertFalse(CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: true,
            entitlementAccountToken: nil,
            currentAccountID: learnerID
        ))
        XCTAssertFalse(CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: true,
            entitlementAccountToken: learnerID,
            currentAccountID: nil
        ))
        XCTAssertFalse(CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: true,
            entitlementAccountToken: UUID(),
            currentAccountID: learnerID
        ))
    }

    func testOnlyPublishedPreviewLessonsAreOpenWithoutPurchase() {
        XCTAssertTrue(CourseAccessPolicy.canOpenLesson(
            courseIsPublished: true,
            lessonIsPreview: true,
            hasVerifiedCourseEntitlement: false
        ))
        XCTAssertFalse(CourseAccessPolicy.canOpenLesson(
            courseIsPublished: false,
            lessonIsPreview: true,
            hasVerifiedCourseEntitlement: false
        ))
        XCTAssertFalse(CourseAccessPolicy.canOpenLesson(
            courseIsPublished: true,
            lessonIsPreview: false,
            hasVerifiedCourseEntitlement: false
        ))
    }

    func testTransactionVerificationWaitsForItsOriginalAccount() {
        let originalAccount = UUID()
        let secondAccount = UUID()

        XCTAssertTrue(CourseAccessPolicy.canSubmitTransactionForVerification(
            transactionAccountToken: originalAccount,
            currentAccountID: originalAccount
        ))
        XCTAssertFalse(CourseAccessPolicy.canSubmitTransactionForVerification(
            transactionAccountToken: originalAccount,
            currentAccountID: secondAccount
        ))
        XCTAssertFalse(CourseAccessPolicy.canSubmitTransactionForVerification(
            transactionAccountToken: originalAccount,
            currentAccountID: nil
        ))
        XCTAssertTrue(CourseAccessPolicy.canSubmitTransactionForVerification(
            transactionAccountToken: nil,
            currentAccountID: originalAccount
        ))
    }

    func testExistingPurchaserKeepsAccessAfterCourseIsUnpublished() {
        XCTAssertTrue(CourseAccessPolicy.canOpenLesson(
            courseIsPublished: false,
            lessonIsPreview: false,
            hasVerifiedCourseEntitlement: true
        ))
    }

    func testAuthErrorsMapToNonTechnicalLocalizedKeys() {
        XCTAssertEqual(
            AuthErrorMessagePolicy.messageKey(for: "invalid_credentials", context: .signIn),
            "Email немесе құпиясөз қате. Қайталап көріңіз."
        )
        XCTAssertEqual(
            AuthErrorMessagePolicy.messageKey(for: "email_not_confirmed", context: .signIn),
            "Кіру алдында Email мекенжайын растаңыз."
        )
        XCTAssertEqual(
            AuthErrorMessagePolicy.messageKey(for: "over_sms_send_rate_limit", context: .signUp),
            "Сұраулар тым жиі жіберілді. Сәл күтіп, қайталап көріңіз."
        )
        XCTAssertEqual(
            AuthErrorMessagePolicy.messageKey(for: "not_admin", context: .adminAction),
            "Бұл әрекетке әкімші рұқсаты қажет."
        )
    }

    func testUnknownAuthErrorUsesOperationSpecificMessageWithoutLeakingServerText() {
        XCTAssertEqual(
            AuthErrorMessagePolicy.messageKey(for: "unknown_server_detail", context: .signIn),
            "Кіру мүмкін болмады. Деректерді тексеріп, қайталап көріңіз."
        )
        XCTAssertNotEqual(
            AuthErrorMessagePolicy.messageKey(for: "unknown_server_detail", context: .signIn),
            "unknown_server_detail"
        )
    }

    func testResumeMergeKeepsNewerDeviceCheckpoint() {
        let older = LocalResumeCheckpoint(positionSeconds: 20, updatedAt: Date(timeIntervalSince1970: 100))
        let newer = LocalResumeCheckpoint(positionSeconds: 45, updatedAt: Date(timeIntervalSince1970: 200))

        let merged = ResumeCheckpointPolicy.merge(
            local: ["lesson-1": newer],
            server: ["lesson-1": older]
        )

        XCTAssertEqual(merged["lesson-1"], newer)
        XCTAssertEqual(
            ResumeCheckpointPolicy.checkpointsToUpload(local: merged, server: ["lesson-1": older])["lesson-1"],
            newer
        )
    }

    func testResumeMergeKeepsNewerServerCheckpoint() {
        let local = LocalResumeCheckpoint(positionSeconds: 20, updatedAt: Date(timeIntervalSince1970: 100))
        let server = LocalResumeCheckpoint(positionSeconds: 45, updatedAt: Date(timeIntervalSince1970: 200))

        let merged = ResumeCheckpointPolicy.merge(
            local: ["lesson-1": local],
            server: ["lesson-1": server]
        )

        XCTAssertEqual(merged["lesson-1"], server)
        XCTAssertTrue(ResumeCheckpointPolicy.checkpointsToUpload(local: merged, server: ["lesson-1": server]).isEmpty)
    }

    func testResumeMergeUsesServerOnTimestampTieAndUploadsOnlyMissingLocalState() {
        let sameTime = Date(timeIntervalSince1970: 100)
        let localTie = LocalResumeCheckpoint(positionSeconds: 20, updatedAt: sameTime)
        let serverTie = LocalResumeCheckpoint(positionSeconds: 25, updatedAt: sameTime)
        let missingServer = LocalResumeCheckpoint(positionSeconds: 10, updatedAt: Date(timeIntervalSince1970: 50))
        let server = ["lesson-1": serverTie]

        let merged = ResumeCheckpointPolicy.merge(
            local: ["lesson-1": localTie, "lesson-2": missingServer],
            server: server
        )
        let pending = ResumeCheckpointPolicy.checkpointsToUpload(local: merged, server: server)

        XCTAssertEqual(merged["lesson-1"], serverTie)
        XCTAssertEqual(pending, ["lesson-2": missingServer])
    }

    func testResumeMergeRejectsInvalidPositions() {
        let valid = LocalResumeCheckpoint(positionSeconds: 5, updatedAt: Date(timeIntervalSince1970: 100))
        let invalid = LocalResumeCheckpoint(positionSeconds: .infinity, updatedAt: Date(timeIntervalSince1970: 200))

        let merged = ResumeCheckpointPolicy.merge(
            local: ["lesson-1": invalid, "lesson-2": valid],
            server: [:]
        )

        XCTAssertEqual(merged, ["lesson-2": valid])
        XCTAssertEqual(ResumeCheckpointPolicy.checkpointsToUpload(local: merged, server: [:]), merged)
    }
}
