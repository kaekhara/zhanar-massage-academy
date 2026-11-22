import Foundation

/// Small, deterministic access rules shared by the iOS app and its unit tests.
public enum CourseAccessPolicy {
    /// A StoreKit entitlement is usable only by the app account recorded in its
    /// `appAccountToken`; a nil token or nil current account never grants access.
    public static func accountOwnsEntitlement(
        isEntitled: Bool,
        entitlementAccountToken: UUID?,
        currentAccountID: UUID?
    ) -> Bool {
        guard isEntitled,
              let entitlementAccountToken,
              let currentAccountID else { return false }
        return entitlementAccountToken == currentAccountID
    }

    /// A purchase tied to a different app account must wait for that account
    /// before its signed transaction is sent for server verification. Older
    /// transactions without a token may still be checked by the server, which
    /// enforces the existing purchase owner in its database.
    public static func canSubmitTransactionForVerification(
        transactionAccountToken: UUID?,
        currentAccountID: UUID?
    ) -> Bool {
        guard let currentAccountID else { return false }
        return transactionAccountToken.map { $0 == currentAccountID } ?? true
    }

    /// Published preview lessons are available without a purchase. All other
    /// lessons require a verified course entitlement. Existing purchasers keep
    /// access when a course is unpublished.
    public static func canOpenLesson(
        courseIsPublished: Bool,
        lessonIsPreview: Bool,
        hasVerifiedCourseEntitlement: Bool
    ) -> Bool {
        hasVerifiedCourseEntitlement || (courseIsPublished && lessonIsPreview)
    }
}
