import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.3"

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
  const publishableKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY")
  const adminKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "unauthorized" })
  if (!supabaseURL || !publishableKey || !adminKey) {
    return json(503, { error: "server_configuration_missing" })
  }

  try {
    const userClient = createClient(supabaseURL, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return json(401, { error: "unauthorized" })

    // Revoke every refresh session before deletion. Already-issued access tokens
    // remain usable until their exp claim, but cannot be refreshed afterwards.
    const revokeResponse = await fetch(`${supabaseURL}/auth/v1/logout?scope=global`, {
      method: "POST",
      headers: {
        apikey: publishableKey,
        Authorization: authorization,
      },
    })
    if (!revokeResponse.ok) {
      console.error("Account session revocation failed", revokeResponse.status)
      return json(503, { error: "session_revocation_failed" })
    }

    const adminClient = createClient(supabaseURL, adminKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id)
    if (deleteError) throw deleteError
    return json(200, { deleted: true })
  } catch {
    console.error("Account deletion failed")
    return json(500, { error: "account_deletion_failed" })
  }
})
