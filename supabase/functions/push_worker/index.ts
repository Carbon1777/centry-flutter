import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") || "").replace(/\\n/g, "\n");

// Must match Android channel id in the app (MainActivity + Flutter local notifications)
// Use a versioned id (Android doesn't upgrade importance for existing channels).
const ANDROID_CHANNEL_ID = "centry_invites_v6";

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

function b64url(input: string) {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(
    JSON.stringify({
      iss: FCM_CLIENT_EMAIL,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );

  const unsigned = `${header}.${payload}`;

  const pem = FCM_PRIVATE_KEY;
  const keyData = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const rawKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    rawKey.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );

  const signature = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${unsigned}.${signature}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const json = await res.json();
  if (!res.ok) throw new Error(`OAuth token error: ${JSON.stringify(json)}`);
  return json.access_token;
}

type Delivery = {
  id: string;
  user_id: string;
  payload: Record<string, unknown> | null;
};

type DeviceToken = {
  token: string;
  platform: string;
};

async function markDelivery(deliveryId: string, patch: Record<string, unknown>) {
  await sbFetch(`/rest/v1/notification_deliveries?id=eq.${deliveryId}`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
}

async function writeDeliveryDebug(deliveryId: string, debugObj: Record<string, unknown>) {
  await sbFetch(`/rest/v1/notification_deliveries?id=eq.${deliveryId}`, {
    method: "PATCH",
    body: JSON.stringify({ debug: debugObj }),
  });
}

async function disableToken(token: string) {
  await sbFetch(`/rest/v1/user_device_tokens?token=eq.${encodeURIComponent(token)}`, {
    method: "PATCH",
    body: JSON.stringify({ enabled: false }),
  });
}

function isPlanInternalInvite(payload: Record<string, unknown>): boolean {
  const t = String(payload["type"] ?? "");
  if (t === "PLAN_INTERNAL_INVITE") return true;

  const inviteId = String(payload["invite_id"] ?? "");
  const planId = String(payload["plan_id"] ?? "");
  return inviteId.length > 0 && planId.length > 0;
}

function isUnregisteredFcmError(text: string): boolean {
  return text.includes('"UNREGISTERED"') || text.includes("UNREGISTERED");
}

function isInternalInviteResult(payload: Record<string, unknown>): boolean {
  const t = String(payload["type"] ?? "");
  if (t !== "PLAN_INTERNAL_INVITE") return false;

  const action = String(payload["action"] ?? "").trim().toUpperCase();
  return action === "ACCEPT" || action === "DECLINE";
}

function safeShort(text: string, maxLen: number): string {
  const s = String(text ?? "");
  if (s.length <= maxLen) return s;
  return s.slice(0, maxLen) + "…";
}

serve(async () => {
  const dRes = await sbFetch(
    `/rest/v1/notification_deliveries?select=id,user_id,payload&channel=eq.PUSH&status=eq.PENDING&limit=50&order=created_at.asc`,
  );
  const deliveries = (await dRes.json()) as Delivery[];
  if (!dRes.ok) {
    return new Response(JSON.stringify({ ok: false, error: deliveries }), { status: 500 });
  }

  if (!Array.isArray(deliveries) || deliveries.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200 });
  }

  const accessToken = await getAccessToken();

  let processed = 0;

  for (const d of deliveries) {
    const deliveryId = d.id;
    const userId = d.user_id;
    const payload = d.payload ?? {};

    const title = String(payload["title"] ?? "Centry");
    const body = String(payload["body"] ?? "");

    const tRes = await sbFetch(
      `/rest/v1/user_device_tokens?select=token,platform&app_user_id=eq.${userId}&enabled=eq.true`,
    );
    const tokens = (await tRes.json()) as DeviceToken[];
    if (!tRes.ok || !Array.isArray(tokens) || tokens.length === 0) {
      await markDelivery(deliveryId, { status: "FAILED", reason: "No device tokens" });
      await writeDeliveryDebug(deliveryId, {
        at: new Date().toISOString(),
        stage: "tokens",
        ok: false,
        error: "No device tokens",
      });
      processed++;
      continue;
    }

    const internalInvite = isPlanInternalInvite(payload);
    const inviteResultForOwner = isInternalInviteResult(payload);

    // ✅ Canon:
    // - Invitee interactive invite (ACCEPT/DECLINE buttons) must be STRICT DATA-ONLY.
    //   No top-level `notification` and no `android.notification`.
    // - Owner result notifications can include OS notification safely.
    const isInviteeInteractiveInvite = internalInvite && !inviteResultForOwner;
    const shouldIncludeNotification = !isInviteeInteractiveInvite;

    let anyOk = false;
    let lastErr = "";

    const debugAttempts: Array<Record<string, unknown>> = [];

    for (const t of tokens) {
      const dataPayload: Record<string, string> = {
        type: "PLAN_INTERNAL_INVITE",
        invite_id: String(payload["invite_id"] ?? ""),
        plan_id: String(payload["plan_id"] ?? ""),
        title: String(payload["title"] ?? title),
        body: String(payload["body"] ?? body),
        action: String(payload["action"] ?? ""),
        // critical for token-path (DECLINE without UI; ACCEPT can use token too)
        action_token: String(payload["action_token"] ?? ""),
        // optional marker for clients/debug
        internal_invite_mode: inviteResultForOwner ? "OWNER_RESULT" : "INVITEE_INVITE",
      };

      const androidConfig = shouldIncludeNotification
        ? {
            priority: "HIGH",
            notification: {
              channel_id: ANDROID_CHANNEL_ID,
              sound: "default",
            },
          }
        : {
            priority: "HIGH",
          };

      const message: Record<string, unknown> = {
        message: {
          token: t.token,
          ...(shouldIncludeNotification ? { notification: { title, body } } : {}),
          data: dataPayload,
          android: androidConfig,
        },
      };

      // For diagnostics only (no secrets): booleans + status/error
      const hasTopNotification = shouldIncludeNotification;
      const hasAndroidNotification = shouldIncludeNotification;

      let attemptOk = false;
      let httpStatus: number | null = null;
      let errShort: string | null = null;

      try {
        const fRes = await fetch(
          `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "content-type": "application/json",
            },
            body: JSON.stringify(message),
          },
        );

        httpStatus = fRes.status;

        if (fRes.ok) {
          attemptOk = true;
          anyOk = true;
        } else {
          const errText = await fRes.text();
          lastErr = errText;
          errShort = safeShort(errText, 300);

          if (isUnregisteredFcmError(errText)) {
            await disableToken(t.token);
          }
        }
      } catch (e) {
        lastErr = String(e);
        errShort = safeShort(String(e), 300);
      }

      debugAttempts.push({
        platform: String(t.platform ?? ""),
        include_notification: shouldIncludeNotification,
        top_notification: hasTopNotification,
        android_notification: hasAndroidNotification,
        fcm_http_status: httpStatus,
        ok: attemptOk,
        error: errShort,
      });
    }

    await markDelivery(
      deliveryId,
      anyOk
        ? { status: "SENT", reason: null }
        : { status: "FAILED", reason: lastErr || "FCM send failed" },
    );

    await writeDeliveryDebug(deliveryId, {
      at: new Date().toISOString(),
      delivery_id: deliveryId,
      user_id: userId,
      classification: {
        internal_invite: internalInvite,
        invite_result_for_owner: inviteResultForOwner,
        invitee_interactive: isInviteeInteractiveInvite,
        include_notification: shouldIncludeNotification,
      },
      attempts: debugAttempts,
    });

    processed++;
  }

  return new Response(JSON.stringify({ ok: true, processed }), { status: 200 });
});