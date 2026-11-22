import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.3"
import { Buffer } from "node:buffer"
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0"
import { canClaimDetachedPurchase } from "./purchase-ownership.js"

const bundleId = "com.kaekhara.Massage-app"

type TransactionPayload = {
  environment?: string
  transactionId?: string
  originalTransactionId?: string
  bundleId?: string
  productId?: string
  purchaseDate?: number
  signedDate?: number
  expiresDate?: number
  appAccountToken?: string
  revocationDate?: number
  type?: string
}

let rootCertificatesPromise: Promise<Buffer[]> | undefined

function readUnverifiedPayload(jws: string): TransactionPayload {
  const parts = jws.split(".")
  if (parts.length !== 3) throw new Error("Invalid JWS")
  const base64 = parts[1].replaceAll("-", "+").replaceAll("_", "/")
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")
  return JSON.parse(atob(padded)) as TransactionPayload
}

async function appleRootCertificates(): Promise<Buffer[]> {
  rootCertificatesPromise ??= (async () => {
    const response = await fetch("https://www.apple.com/certificateauthority/AppleRootCA-G3.cer")
    if (!response.ok) throw new Error("Apple root certificate unavailable")
    return [Buffer.from(await response.arrayBuffer())]
  })()
  const pending = rootCertificatesPromise
  try {
    return await pending
  } catch (error) {
    // A transient Apple/network failure must not poison this warm instance.
    if (rootCertificatesPromise === pending) rootCertificatesPromise = undefined
    throw error
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  })
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" })

  const authorization = request.headers.get("Authorization")
  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}") as Record<string, string>
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>
  const anonKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "unauthorized" })
  if (!supabaseURL || !anonKey || !serviceRoleKey) {
    return json(503, { error: "server_configuration_missing" })
  }

  try {
    const requestBody = await request.json() as { signedTransactionInfo?: unknown }
    const signedTransactionInfo = requestBody.signedTransactionInfo
    if (typeof signedTransactionInfo !== "string" || signedTransactionInfo.length > 64_000) {
      return json(400, { error: "invalid_transaction" })
    }

    const userClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return json(401, { error: "unauthorized" })

    const unverified = readUnverifiedPayload(signedTransactionInfo)
    const environment = unverified.environment === "Production"
      ? Environment.PRODUCTION
      : unverified.environment === "Sandbox"
      ? Environment.SANDBOX
      : null
    if (!environment) return json(400, { error: "unsupported_environment" })

    const appAppleIDText = Deno.env.get("APPLE_APP_ID")
    if (environment === Environment.PRODUCTION && !appAppleIDText) {
      return json(503, { error: "production_app_id_not_configured" })
    }
    const appAppleID = appAppleIDText ? Number(appAppleIDText) : undefined
    if (appAppleIDText && (!Number.isSafeInteger(appAppleID) || Number(appAppleID) <= 0)) {
      return json(503, { error: "production_app_id_invalid" })
    }

    const verifier = new SignedDataVerifier(
      await appleRootCertificates(),
      true,
      environment,
      bundleId,
      appAppleID,
    )
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransactionInfo)
    const transactionId = transaction.transactionId
    const originalTransactionId = transaction.originalTransactionId
    const productID = transaction.productId
    const purchaseDate = transaction.purchaseDate
    const accountToken = transaction.appAccountToken?.toLowerCase()

    if (transaction.bundleId !== bundleId || transaction.type !== "Non-Consumable") {
      return json(403, { error: "transaction_not_for_this_app" })
    }
    if (!transactionId || !originalTransactionId || !productID || !purchaseDate) {
      return json(400, { error: "transaction_incomplete" })
    }
    if (transaction.expiresDate && transaction.expiresDate <= Date.now()) {
      return json(403, { error: "transaction_expired" })
    }

    const adminHeaders = { apikey: serviceRoleKey }
    const previousURL = new URL("/rest/v1/verified_purchases", supabaseURL)
    previousURL.search = new URLSearchParams({
      select: "user_id,product_id,revoked_at,last_notification_signed_at",
      transaction_id: `eq.${transactionId}`,
    }).toString()
    const respondWithPersistedState = async (): Promise<Response> => {
      // The notification endpoint may have changed the row during this request.
      const stateResponse = await fetch(previousURL, { headers: adminHeaders })
      if (!stateResponse.ok) throw new Error("Purchase state lookup failed")
      const stateRows = await stateResponse.json() as Array<{
        user_id: string | null
        product_id: string
        revoked_at: string | null
      }>
      const state = stateRows[0]
      if (!state || state.user_id !== user.id || state.product_id !== productID) {
        return json(409, { error: "transaction_ownership_changed" })
      }
      return json(200, { productID, revoked: state.revoked_at !== null })
    }
    const previousResponse = await fetch(previousURL, { headers: adminHeaders })
    if (!previousResponse.ok) throw new Error("Purchase lookup failed")
    const previousRows = await previousResponse.json() as Array<{
      user_id: string | null
      product_id: string
      revoked_at: string | null
      last_notification_signed_at?: string | null
    }>
    const previous = previousRows[0]
    const belongsToCurrentAccount = accountToken === user.id.toLowerCase()
    const alreadyOwnedByCurrentAccount = previous?.user_id === user.id
    const canClaimDetached = canClaimDetachedPurchase(previous?.user_id, accountToken, user.id)
    if (!belongsToCurrentAccount && !alreadyOwnedByCurrentAccount && !canClaimDetached) {
      return json(403, { error: "account_mismatch" })
    }
    if (previous && previous.user_id !== null && previous.user_id !== user.id) {
      return json(409, { error: "transaction_already_claimed" })
    }
    if (previous && previous.product_id !== productID) {
      return json(409, { error: "transaction_product_mismatch" })
    }

    const courseURL = new URL("/rest/v1/courses", supabaseURL)
    courseURL.search = new URLSearchParams({
      select: "store_product_id,is_published",
      store_product_id: `eq.${productID}`,
    }).toString()
    const courseResponse = await fetch(courseURL, { headers: adminHeaders })
    if (!courseResponse.ok) throw new Error("Course lookup failed")
    const courses = await courseResponse.json() as Array<{ store_product_id: string; is_published: boolean }>
    const course = courses[0]
    if (!course || (!course.is_published && !alreadyOwnedByCurrentAccount && !canClaimDetached)) {
      return json(403, { error: "course_not_available_for_new_purchases" })
    }

    // A signed transaction can be replayed after a newer refund notification.
    // Never let an old transaction snapshot overwrite the notification's state.
    if (previous) {
      if (canClaimDetached) {
        const reclaimURL = new URL("/rest/v1/verified_purchases", supabaseURL)
        reclaimURL.search = new URLSearchParams({
          transaction_id: `eq.${transactionId}`,
          user_id: "is.null",
        }).toString()
        const reclaim = await fetch(reclaimURL, {
          method: "PATCH",
          headers: {
            ...adminHeaders,
            "Content-Type": "application/json",
            Prefer: "return=representation",
          },
          body: JSON.stringify({ user_id: user.id }),
        })
        if (!reclaim.ok) throw new Error("Purchase reclaim failed")
        const reclaimedRows = await reclaim.json() as Array<{ user_id?: string | null }>
        if (!reclaimedRows.some((row) => row.user_id === user.id)) {
          const ownershipResponse = await fetch(previousURL, { headers: adminHeaders })
          if (!ownershipResponse.ok) throw new Error("Purchase ownership check failed")
          const ownershipRows = await ownershipResponse.json() as Array<{ user_id: string | null }>
          if (ownershipRows[0]?.user_id !== user.id) {
            return json(409, { error: "transaction_already_claimed" })
          }
        }
      }
      const latestNotification = previous.last_notification_signed_at
        ? Date.parse(previous.last_notification_signed_at)
        : null
      const transactionIsNewerThanNotification = latestNotification === null ||
        (typeof transaction.signedDate === "number" && transaction.signedDate >= latestNotification)
      if (
        transaction.revocationDate != null &&
        transactionIsNewerThanNotification &&
        !previous.revoked_at
      ) {
        const revokeURL = new URL("/rest/v1/verified_purchases", supabaseURL)
        revokeURL.search = new URLSearchParams({
          transaction_id: `eq.${transactionId}`,
          revoked_at: "is.null",
          last_notification_signed_at: previous.last_notification_signed_at
            ? `eq.${previous.last_notification_signed_at}`
            : "is.null",
        }).toString()
        const revoke = await fetch(revokeURL, {
          method: "PATCH",
          headers: {
            ...adminHeaders,
            "Content-Type": "application/json",
            Prefer: "return=minimal",
          },
          body: JSON.stringify({ revoked_at: new Date(transaction.revocationDate).toISOString() }),
        })
        if (!revoke.ok) throw new Error("Purchase revocation update failed")
      }
      return await respondWithPersistedState()
    }

    const revokedAt = transaction.revocationDate
      ? new Date(transaction.revocationDate).toISOString()
      : null
    const insertURL = new URL("/rest/v1/verified_purchases", supabaseURL)
    const insertResponse = await fetch(insertURL, {
      method: "POST",
      headers: {
        ...adminHeaders,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({
        transaction_id: transactionId,
        original_transaction_id: originalTransactionId,
        user_id: user.id,
        product_id: productID,
        purchased_at: new Date(purchaseDate).toISOString(),
        revoked_at: revokedAt,
      }),
    })
    if (!insertResponse.ok) {
      // A concurrent request or notification may have inserted this transaction.
      // Do not retry as an upsert: that could overwrite a newer refund state.
      const latestResponse = await fetch(previousURL, { headers: adminHeaders })
      if (!latestResponse.ok) throw new Error("Purchase write failed")
      const latestRows = await latestResponse.json() as Array<{ user_id: string | null; product_id: string; revoked_at: string | null }>
      const latest = latestRows[0]
      if (latest?.product_id === productID && canClaimDetachedPurchase(latest.user_id, accountToken, user.id)) {
        // A notification may create a detached row between the initial lookup and
        // insert. Attach ownership only; leave any newer refund state untouched.
        const claimURL = new URL("/rest/v1/verified_purchases", supabaseURL)
        claimURL.search = new URLSearchParams({
          transaction_id: `eq.${transactionId}`,
          user_id: "is.null",
        }).toString()
        const claim = await fetch(claimURL, {
          method: "PATCH",
          headers: {
            ...adminHeaders,
            "Content-Type": "application/json",
            Prefer: "return=representation",
          },
          body: JSON.stringify({ user_id: user.id }),
        })
        if (!claim.ok) throw new Error("Purchase claim after notification failed")
        const claimedRows = await claim.json() as Array<{ user_id?: string | null }>
        if (claimedRows.some((row) => row.user_id === user.id)) {
          return await respondWithPersistedState()
        }
      }
      if (latest?.user_id !== user.id || latest.product_id !== productID) {
        const ownershipResponse = await fetch(previousURL, { headers: adminHeaders })
        if (!ownershipResponse.ok) throw new Error("Purchase ownership check failed")
        const ownershipRows = await ownershipResponse.json() as Array<{ user_id: string | null; product_id: string; revoked_at: string | null }>
        const owned = ownershipRows[0]
        if (owned?.user_id === user.id && owned.product_id === productID) {
          return await respondWithPersistedState()
        }
        return json(409, { error: "transaction_already_claimed" })
      }
      return await respondWithPersistedState()
    }

    return await respondWithPersistedState()
  } catch {
    console.error("StoreKit transaction verification failed")
    return json(400, { error: "transaction_verification_failed" })
  }
})
