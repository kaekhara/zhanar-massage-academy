/**
 * A detached transaction may only be attached to the ZHANAR account named by
 * Apple's verified appAccountToken. This is also used for notification-first
 * rows whose user_id is null before the purchase is verified by the app.
 * @param {string | null | undefined} storedUserID
 * @param {string | null | undefined} appAccountToken
 * @param {string | null | undefined} currentUserID
 * @returns {boolean}
 */
export function canClaimDetachedPurchase(storedUserID, appAccountToken, currentUserID) {
  return storedUserID === null &&
    typeof appAccountToken === "string" &&
    typeof currentUserID === "string" &&
    appAccountToken.toLowerCase() === currentUserID.toLowerCase()
}
