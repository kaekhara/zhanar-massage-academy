import test from "node:test"
import assert from "node:assert/strict"
import { canClaimDetachedPurchase } from "./purchase-ownership.js"

const currentUserID = "a1b2c3d4-e5f6-4789-a012-3456789abcde"

test("allows a detached notification row for the account bound by Apple's token", () => {
  assert.equal(canClaimDetachedPurchase(null, currentUserID.toUpperCase(), currentUserID), true)
})

test("rejects transfer of a deleted account's transaction to a different account", () => {
  assert.equal(canClaimDetachedPurchase(null, currentUserID, "different-user-id"), false)
})

test("rejects detached rows without a verified account token", () => {
  assert.equal(canClaimDetachedPurchase(null, undefined, currentUserID), false)
  assert.equal(canClaimDetachedPurchase(null, null, currentUserID), false)
})

test("does not authorize rows owned by another account or rows that do not exist", () => {
  assert.equal(canClaimDetachedPurchase("other-user-id", currentUserID, currentUserID), false)
  assert.equal(canClaimDetachedPurchase(undefined, currentUserID, currentUserID), false)
})

test("requires string identifiers", () => {
  assert.equal(canClaimDetachedPurchase(null, {}, currentUserID), false)
  assert.equal(canClaimDetachedPurchase(null, currentUserID, null), false)
})
