import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") || "").replace(/\\n/g, "\n");

type DeviceToken = {
  token: string;
  platform: string; // android|ios
};

async function sbFetch(path: string, init?: RequestInit): Promise<Response> {
  const url = `${SUPABASE_URL}${path}`;
  const headers = new Headers(init?.headers || {});
  headers.set("apikey", SUPABASE_SERVICE_ROLE_KEY);
  headers.set("Authorization", `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`);
  headers.set("Content-Type", "application/json");
  return await fetch(url, { ...init, headers });
}

async function markDelivery(
  deliveryId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  await sbFetch(`/rest/v1/notification_deliveries?id=eq.${deliveryId}`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
}

async function disableToken(token: string): Promise<void> {
  await sbFetch(`/rest/v1/user_device_tokens?token=eq.${token}`, {
    method: "PATCH",
    body: JSON.stringify({ enabled: false }),
  });
}

function isUnregisteredFcmError(errText: string): boolean {
  const s = String(errText ?? "").toLowerCase();
  return s.includes("unregistered") || s.includes("registration-token-not-registered");
}

function isInternalInvite(payload: Record<string, unknown>): boolean {
  return String(payload["type"] ?? "") === "PLAN_INTERNAL_INVITE";
}

function isInternalInviteResult(payload: Record<string, unknown>): boolean {
  // Our canonical owner-result marker: payload.action = ACCEPT|DECLINE
  // (Invitee invite may also have action token; owner-result is produced after invitee acts.)
  const action = String(payload["action"] ?? "").trim().toUpperCase();
  return action === "ACCEPT" || action === "DECLINE";
}

function isPlanMemberLeft(payload: Record<string, unknown>): boolean {
  return String(payload["type"] ?? "") === "PLAN_MEMBER_LEFT";
}

function safeShort(text: string, maxLen: number): string {
  const s = String(text ?? "");
  if (s.length <= maxLen) return s;
  return s.slice(0, maxLen) + "…";
}

async function getAccessToken(): Promise<string> {
  // Simple JWT service account flow for FCM v1.
  // Keeping it compact; assumes correct env vars.
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 60 * 60,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/g, "");

  const unsigned = `${enc(header)}.${enc(claimSet)}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    new TextEncoder().encode(FCM_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sigBuf = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");

  const jwt = `${unsigned}.${sig}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    throw new Error(`oauth token error ${res.status}: ${await res.text()}`);
  }
  const json = await res.json();
  return String(json.access_token);
}

serve(async () => {
  const dRes = await sbFetch(
    `/rest/v1/notification_deliveries?select=id,user_id,payload&channel=eq.PUSH&status=eq.PENDING&limit=50&order=created_at.asc`,
  );
  const deliveries = (await dRes.json()) as Array<
    { id: string; user_id: string; payload: Record<string, unknown> }
  >;

  if (!dRes.ok) {
    return new Response(await dRes.text(), { status: 500 });
  }

  if (!Array.isArray(deliveries) || deliveries.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  let accessToken = "";
  try {
    accessToken = await getAccessToken();
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: `getAccessToken failed: ${String(e)}` }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

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
      await markDelivery(deliveryId, {
        status: "SKIPPED",
        reason: "NO_TOKENS",
      });
      processed++;
      continue;
    }

    const internalInvite = isInternalInvite(payload);
    const memberLeft = isPlanMemberLeft(payload);
    const inviteResultForOwner = isInternalInviteResult(payload);
    const isInviteeInteractiveInvite = internalInvite && !inviteResultForOwner;

    // PLAN_MEMBER_LEFT: enrich title/body with server-provided context (nickname + plan title) for local-notification UX.
    const leftNickname = String(payload["left_nickname"] ?? "").trim();
    const planTitle = String(payload["plan_title"] ?? "").trim();

    const memberLeftTitle =
      leftNickname.length > 0 ? `${leftNickname} покинул план` : String(payload["title"] ?? title);

    const memberLeftBody =
      leftNickname.length > 0 && planTitle.length > 0
        ? `${leftNickname} покинул план «${planTitle}».`
        : planTitle.length > 0
          ? `Участник покинул план «${planTitle}».`
          : String(payload["body"] ?? body);

    // ✅ Canon (server-first UX):
    // - PLAN_INTERNAL_INVITE (invitee invite OR owner result): STRICT DATA-ONLY.
    //   Reason: avoid OS auto-notification duplicates and route everything through app-controlled UI.
    // - PLAN_MEMBER_LEFT: STRICT DATA-ONLY (app shows local notification with action button).
    // - Other notification types may include OS notification.
    const shouldIncludeNotification = !(internalInvite || memberLeft);
    let anyOk = false;
    let lastErr = "";

    const debugAttempts: Array<Record<string, unknown>> = [];

    for (const t of tokens) {
      const type = String(payload["type"] ?? "");
      const baseData: Record<string, string> = {
        type: type.length > 0 ? type : "UNKNOWN",
        title: memberLeft ? memberLeftTitle : String(payload["title"] ?? title),
        body: memberLeft ? memberLeftBody : String(payload["body"] ?? body),
        plan_id: String(payload["plan_id"] ?? ""),
      };

      const dataPayload: Record<string, string> = internalInvite
        ? {
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
          }
        : memberLeft
        ? {
            type: "PLAN_MEMBER_LEFT",
            plan_id: String(payload["plan_id"] ?? ""),
            plan_title: planTitle,
            left_user_id: String(payload["left_user_id"] ?? ""),
            left_nickname: leftNickname,
            title: memberLeftTitle,
            body: memberLeftBody,
          }
        : baseData;

      const androidConfig = shouldIncludeNotification
        ? {
            priority: "HIGH",
            notification: {
              title: String(payload["title"] ?? title),
              body: String(payload["body"] ?? body),
            },
          }
        : {
            priority: "HIGH",
          };

      const apnsConfig = shouldIncludeNotification
        ? {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                alert: {
                  title: String(payload["title"] ?? title),
                  body: String(payload["body"] ?? body),
                },
                sound: "default",
              },
            },
          }
        : {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                // data-only
                "content-available": 1,
              },
            },
          };

      const msg = {
        message: {
          token: t.token,
          data: Object.fromEntries(
            Object.entries(dataPayload).map(([k, v]) => [k, String(v)]),
          ),
          android: androidConfig,
          apns: apnsConfig,
        },
      };

      let errShort = "";
      let ok = false;

      try {
        const fRes = await fetch(
          `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(msg),
          },
        );

        if (fRes.ok) {
          ok = true;
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
        internal_invite: internalInvite,
        internal_invite_mode: internalInvite
          ? (inviteResultForOwner ? "OWNER_RESULT" : "INVITEE_INVITE")
          : null,
        invitee_interactive_invite: isInviteeInteractiveInvite,
        member_left: memberLeft,
        ok,
        err_short: errShort,
      });
    }

    if (anyOk) {
      await markDelivery(deliveryId, {
        status: "SENT",
        reason: null,
        debug: { attempts: debugAttempts },
      });
    } else {
      await markDelivery(deliveryId, {
        status: "FAILED",
        reason: safeShort(lastErr, 400),
        debug: { attempts: debugAttempts },
      });
    }

    processed++;
  }

  return new Response(JSON.stringify({ ok: true, processed }), {
    headers: { "Content-Type": "application/json" },
  });
});