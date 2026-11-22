import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.3"

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json; charset=utf-8" },
    status,
  })
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" })

  const authorization = request.headers.get("Authorization")
  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}") as Record<string, string>
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>
  const publishableKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "unauthorized" })
  if (!supabaseURL || !publishableKey || !serviceRoleKey) {
    return json(503, { error: "server_configuration_missing" })
  }

  try {
    const body = await request.json() as {
      assetType?: unknown
      courseID?: unknown
      fileExtension?: unknown
      contentType?: unknown
      fileSize?: unknown
    }
    if (
      body.assetType !== "cover" ||
      typeof body.courseID !== "string" || body.courseID.length < 1 || body.courseID.length > 100 ||
      typeof body.fileExtension !== "string" ||
      typeof body.contentType !== "string" ||
      typeof body.fileSize !== "number" || !Number.isInteger(body.fileSize) ||
      body.fileSize < 1 || body.fileSize > 5_000_000
    ) return json(400, { error: "invalid_cover_metadata" })

    const allowedContentTypes: Record<string, string> = {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      webp: "image/webp",
    }
    const fileExtension = body.fileExtension.toLowerCase()
    if (allowedContentTypes[fileExtension] !== body.contentType) {
      return json(400, { error: "unsupported_cover_type" })
    }

    const userClient = createClient(supabaseURL, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return json(401, { error: "unauthorized" })

    const adminClient = createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: role, error: roleError } = await adminClient
      .from("course_admins")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle()
    if (roleError) throw roleError
    if (!role) return json(403, { error: "admin_access_required" })

    const { data: course, error: courseError } = await adminClient
      .from("courses")
      .select("store_product_id")
      .eq("id", body.courseID)
      .maybeSingle()
    if (courseError) throw courseError
    if (!course || !/^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$/.test(course.store_product_id)) {
      return json(404, { error: "course_not_found" })
    }

    const path = `${course.store_product_id}/${crypto.randomUUID()}.${fileExtension}`
    const { data: upload, error: uploadError } = await adminClient.storage
      .from("course-covers")
      .createSignedUploadUrl(path)
    if (uploadError || !upload) throw uploadError ?? new Error("Could not create signed upload")
    return json(200, { path, token: upload.token })
  } catch {
    console.error("Admin course cover upload URL creation failed")
    return json(500, { error: "cover_upload_setup_failed" })
  }
})
