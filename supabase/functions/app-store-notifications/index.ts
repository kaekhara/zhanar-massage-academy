import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { Buffer } from "node:buffer"
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0"

const bundleId = "com.kaekhara.Massage-app"

type UnverifiedPayload = {
  data?: { environment?: string; signedTransactionInfo?: string }
}
type TransactionPayload = {
  transactionId?: string
  originalTransactionId?: string
  purchaseDate?: number
  bundleId?: string
  productId?: string
  revocationDate?: number
}
type NotificationPayload = {
  notificationType?: string
  notificationUUID?: string
  signedDate?: number
  data?: { signedTransactionInfo?: string }
}

const MAX_NOTIFICATION_BODY_BYTES = 300_000

class RequestBodyTooLarge extends Error {}

let rootCertificatesPromise: Promise<Buffer[]> | undefined

function decodeUnverifiedPayload(jws: string): UnverifiedPayload {
  const parts = jws.split(".")
  if (parts.length !== 3) throw new Error("Invalid JWS")
  const base64 = parts[1].replaceAll("-", "+").replaceAll("_", "/")
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")
  return JSON.parse(atob(padded)) as UnverifiedPayload
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

async function readJSONBody(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("Content-Length")
  if (declaredLength !== null) {
    const parsedLength = Number(declaredLength)
    if (!Number.isSafeInteger(parsedLength) || parsedLength < 0) {
      throw new Error("Invalid Content-Length")
    }
    if (parsedLength > MAX_NOTIFICATION_BODY_BYTES) {
      throw new RequestBodyTooLarge()
    }
  }

  if (!request.body) throw new Error("Missing request body")
  const reader = request.body.getReader()
  const chunks: Uint8Array[] = []
  let totalBytes = 0
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      totalBytes += value.byteLength
      if (totalBytes > MAX_NOTIFICATION_BODY_BYTES) {
        await reader.cancel()
        throw new RequestBodyTooLarge()
      }
      chunks.push(value)
    }
  } finally {
    reader.releaseLock()
  }

  const body = new Uint8Array(totalBytes)
  let offset = 0
  for (const chunk of chunks) {
    body.set(chunk, offset)
    offset += chunk.byteLength
  }
  return JSON.parse(new TextDecoder().decode(body)) as unknown
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" })
  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>
  const serviceRoleKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!supabaseURL || !serviceRoleKey) {
    return json(503, { error: "server_configuration_missing" })
  }

  try {
    const body = await readJSONBody(request) as { signedPayload?: unknown }
    if (typeof body.signedPayload !== "string" || body.signedPayload.length > 256_000) {
      return json(400, { error: "invalid_notification" })
    }
    const unverified = decodeUnverifiedPayload(body.signedPayload)
    const environment = unverified.data?.environment === "Production"
      ? Environment.PRODUCTION
      : unverified.data?.environment === "Sandbox"
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
    const notification = await verifier.verifyAndDecodeNotification(body.signedPayload) as NotificationPayload
    const notificationType = notification.notificationType
    const signedTransactionInfo = notification.data?.signedTransactionInfo
    if (!signedTransactionInfo || !["REFUND", "REVOKE", "REFUND_REVERSED"].includes(notificationType ?? "")) {
      return json(200, { received: true })
    }
    const notificationUUID = notification.notificationUUID
    const notificationSignedDate = notification.signedDate
    if (
      typeof notificationUUID !== "string" || !notificationUUID ||
      typeof notificationSignedDate !== "number" || !Number.isFinite(notificationSignedDate) || notificationSignedDate <= 0
    ) return json(400, { error: "notification_metadata_incomplete" })

    const transaction = await verifier.verifyAndDecodeTransaction(signedTransactionInfo) as TransactionPayload
    if (
      transaction.bundleId !== bundleId ||
      !transaction.transactionId ||
      !transaction.productId
    ) return json(200, { received: true })

    const headers = { apikey: serviceRoleKey, "Content-Type": "application/json" }
    const lookupURL = new URL("/rest/v1/verified_purchases", supabaseURL)
    lookupURL.search = new URLSearchParams({
      select: "transaction_id,product_id,last_notification_uuid",
      transaction_id: `eq.${transaction.transactionId}`,
    }).toString()
    const lookup = await fetch(lookupURL, { headers })
    if (!lookup.ok) throw new Error("Purchase lookup failed")
    let matches = await lookup.json() as Array<{
      transaction_id: string
      product_id: string
      last_notification_uuid: string | null
    }>
    if (!matches.length) {
      // A refund can reach us before the client has submitted its purchase JWS.
      // Keep the signed Apple state detached so a later verification cannot
      // recreate access from an older purchase snapshot.
      if (!transaction.originalTransactionId || !transaction.purchaseDate) {
        return json(200, { received: true })
      }
      const signedAt = new Date(notificationSignedDate).toISOString()
      const revokedAt = notificationType === "REFUND_REVERSED"
        ? null
        : new Date(transaction.revocationDate ?? Date.now()).toISOString()
      const insert = await fetch(new URL("/rest/v1/verified_purchases", supabaseURL), {
        method: "POST",
        headers: { ...headers, Prefer: "return=minimal" },
        body: JSON.stringify({
          transaction_id: transaction.transactionId,
          original_transaction_id: transaction.originalTransactionId,
          user_id: null,
          product_id: transaction.productId,
          purchased_at: new Date(transaction.purchaseDate).toISOString(),
          revoked_at: revokedAt,
          last_notification_signed_at: signedAt,
          last_notification_uuid: notificationUUID,
        }),
      })
      if (insert.ok) return json(200, { received: true })

      // Another verifier or notification may have inserted the transaction
      // after the first lookup. Re-read and apply normal ordering checks below.
      const retryLookup = await fetch(lookupURL, { headers })
      if (!retryLookup.ok) throw new Error("Purchase lookup failed")
      matches = await retryLookup.json() as typeof matches
      if (!matches.length) throw new Error("Purchase insert failed")
    }
    if (matches[0].product_id !== transaction.productId) {
      return json(200, { received: true })
    }
    if (matches[0].last_notification_uuid === notificationUUID) {
      return json(200, { received: true })
    }

    const updateURL = new URL("/rest/v1/verified_purchases", supabaseURL)
    const signedAt = new Date(notificationSignedDate).toISOString()
    updateURL.searchParams.set("transaction_id", `eq.${transaction.transactionId}`)
    // Apple can retry and reorder V2 notifications. Only accept a snapshot newer
    // than the one already applied; signedDate remains stable across retries.
    updateURL.searchParams.set(
      "or",
      `(last_notification_signed_at.is.null,last_notification_signed_at.lt.${signedAt})`,
    )
    const revokedAt = notificationType === "REFUND_REVERSED"
      ? null
      : new Date(transaction.revocationDate ?? Date.now()).toISOString()
    const update = await fetch(updateURL, {
      method: "PATCH",
      headers: { ...headers, Prefer: "return=minimal" },
      body: JSON.stringify({
        revoked_at: revokedAt,
        last_notification_signed_at: signedAt,
        last_notification_uuid: notificationUUID,
      }),
    })
    if (!update.ok) throw new Error("Purchase update failed")
    return json(200, { received: true })
  } catch (error) {
    if (error instanceof RequestBodyTooLarge) {
      return json(413, { error: "payload_too_large" })
    }
    console.error("App Store notification verification failed")
    return json(400, { error: "notification_verification_failed" })
  }
})
