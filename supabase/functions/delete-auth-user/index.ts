import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // 1. Verify user JWT via Supabase Auth API
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${token}`,
      },
    });
    if (!userRes.ok) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    const authUser = await userRes.json();
    const authUid: string = authUser.id;

    // 2. Resolve app_user_id
    const appUserRes = await sbFetch(
      `/rest/v1/app_users?select=id&auth_user_id=eq.${authUid}&limit=1`
    );
    if (!appUserRes.ok) {
      return jsonResponse({ error: "Failed to resolve user" }, 500);
    }
    const appUsers = await appUserRes.json();
    if (!appUsers?.length) {
      return jsonResponse({ error: "User not found" }, 404);
    }
    const appUserId: string = appUsers[0].id;

    // 3. Verify there is a pending deletion request for this user
    const jobRes = await sbFetch(
      `/rest/v1/account_deletion_jobs?select=id,status&app_user_id=eq.${appUserId}&status=eq.PENDING&limit=1`
    );
    if (!jobRes.ok) {
      return jsonResponse({ error: "Failed to check deletion status" }, 500);
    }
    const jobs = await jobRes.json();
    if (!jobs?.length) {
      return jsonResponse(
        { error: "No pending deletion request found. Request deletion first." },
        409
      );
    }

    // 4. Delete the auth user via Admin API
    const deleteRes = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users/${authUid}`,
      {
        method: "DELETE",
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );

    if (!deleteRes.ok) {
      const errText = await deleteRes.text();
      console.error(`Auth user deletion failed: ${deleteRes.status} ${errText}`);
      return jsonResponse(
        { error: "Failed to delete auth user", detail: errText },
        500
      );
    }

    // 5. Mark deletion job as completed
    await sbFetch(
      `/rest/v1/account_deletion_jobs?id=eq.${jobs[0].id}`,
      {
        method: "PATCH",
        body: JSON.stringify({
          status: "COMPLETED",
          completed_at: new Date().toISOString(),
        }),
        headers: { Prefer: "return=minimal" },
      }
    );

    return jsonResponse({ message: "Account deleted successfully" });
  } catch (err) {
    console.error("delete-auth-user error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

// ─── Helpers ───

async function sbFetch(path: string, init?: RequestInit) {
  return fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      ...(init?.headers || {}),
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
  });
}

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
