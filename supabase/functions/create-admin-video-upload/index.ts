import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.3"

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  })
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
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
      lessonID?: unknown
      fileExtension?: unknown
      contentType?: unknown
      fileSize?: unknown
    }
    if (
      typeof body.lessonID !== "string" || body.lessonID.length < 1 || body.lessonID.length > 200 ||
      typeof body.fileExtension !== "string" ||
      typeof body.contentType !== "string" ||
      typeof body.fileSize !== "number" || !Number.isInteger(body.fileSize) ||
      body.fileSize < 1 || body.fileSize > 50_000_000
    ) return json(400, { error: "invalid_video_metadata" })

    const allowedContentTypes: Record<string, string> = {
      mp4: "video/mp4",
      mov: "video/quicktime",
      m4v: "video/x-m4v",
    }
    const fileExtension = body.fileExtension.toLowerCase()
    if (allowedContentTypes[fileExtension] !== body.contentType) {
      return json(400, { error: "unsupported_video_type" })
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

    const { data: lesson, error: lessonError } = await adminClient
      .from("lessons")
      .select("section_id")
      .eq("id", body.lessonID)
      .maybeSingle()
    if (lessonError) throw lessonError
    if (!lesson) return json(404, { error: "lesson_not_found" })

    const { data: section, error: sectionError } = await adminClient
      .from("course_sections")
      .select("course_id")
      .eq("id", lesson.section_id)
      .maybeSingle()
    if (sectionError) throw sectionError
    if (!section) return json(404, { error: "course_not_found" })

    const { data: course, error: courseError } = await adminClient
      .from("courses")
      .select("store_product_id")
      .eq("id", section.course_id)
      .maybeSingle()
    if (courseError) throw courseError
    if (!course || !/^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$/.test(course.store_product_id)) {
      return json(409, { error: "course_product_id_invalid" })
    }

    const path = `${course.store_product_id}/${crypto.randomUUID()}.${fileExtension}`
    const { data: upload, error: uploadError } = await adminClient.storage
      .from("course-videos")
      .createSignedUploadUrl(path)
    if (uploadError || !upload) throw uploadError ?? new Error("Could not create signed upload")

    return json(200, { path, token: upload.token })
  } catch (error) {
    console.error("Admin video upload URL creation failed", error)
    return json(500, { error: "video_upload_setup_failed" })
  }
})
