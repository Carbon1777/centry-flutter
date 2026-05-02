// Apple Guideline 1.2 (Safety / UGC) — Edge Function для email-уведомлений модератору.
// Триггерится из Postgres через pg_net.http_post после INSERT в content_reports.
// Маршрутизирует жалобу на moderation@ или abuse@ по тяжести категории.
// См. /TZ_apple_ugc_compliance.md (раздел 2.7).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { SMTPClient } from "denomailer";

// Env читаем без падения на старте — иначе функция не задеплоится до установки секретов.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SMTP_HOST = Deno.env.get("SMTP_HOST") ?? "";
const SMTP_PORT = parseInt(Deno.env.get("SMTP_PORT") || "465", 10);
const SMTP_USER = Deno.env.get("SMTP_USER") ?? "";
const SMTP_PASS = Deno.env.get("SMTP_PASS") ?? "";
const SMTP_FROM = Deno.env.get("SMTP_FROM") || SMTP_USER;
const MAIL_TO_REGULAR = Deno.env.get("MAIL_TO_REGULAR") || SMTP_USER;
const MAIL_TO_CRITICAL = Deno.env.get("MAIL_TO_CRITICAL") || MAIL_TO_REGULAR;

// Bearer-токен для аутентификации между Postgres-триггером и Edge Function.
// Должен совпадать с app.notify_moderator_token в Postgres GUC.
const NOTIFY_TOKEN = Deno.env.get("NOTIFY_TOKEN") ?? "";

function checkConfig(): string | null {
  if (!SUPABASE_URL) return "SUPABASE_URL not set";
  if (!SUPABASE_SERVICE_ROLE_KEY) return "SUPABASE_SERVICE_ROLE_KEY not set";
  if (!SMTP_HOST) return "SMTP_HOST not set";
  if (!SMTP_USER) return "SMTP_USER not set";
  if (!SMTP_PASS) return "SMTP_PASS not set";
  if (!NOTIFY_TOKEN) return "NOTIFY_TOKEN not set";
  return null;
}

const CRITICAL_CATEGORIES = new Set(["csae", "violence", "self_harm", "illegal"]);

const CATEGORY_RU: Record<string, string> = {
  spam: "Спам или реклама",
  harassment: "Оскорбления / агрессия",
  hate: "Ненависть / дискриминация",
  sexual: "Сексуальный контент",
  impersonation: "Выдача за другого человека",
  other: "Другое",
  csae: "Угроза безопасности детей (CSAE)",
  violence: "Насилие / угрозы",
  self_harm: "Самоповреждение / суицид",
  illegal: "Незаконная деятельность",
};

const TARGET_TYPE_RU: Record<string, string> = {
  profile: "Профиль",
  photo: "Фото",
  plan_chat_message: "Сообщение в чате плана",
  private_chat_message: "Приватное сообщение",
  plan: "План",
  place: "Место",
};

interface ContentReport {
  id: string;
  reporter_app_user_id: string;
  target_type: string;
  target_id: string;
  target_owner_app_user_id: string | null;
  category: string;
  comment: string | null;
  content_snapshot: Record<string, unknown> | null;
  status: string;
  created_at: string;
}

async function sbFetch(path: string): Promise<Response> {
  return fetch(`${SUPABASE_URL}${path}`, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });
}

async function getReport(reportId: string): Promise<ContentReport | null> {
  const r = await sbFetch(
    `/rest/v1/content_reports?id=eq.${reportId}&select=*&limit=1`,
  );
  const arr = await r.json();
  return arr?.[0] ?? null;
}

async function getNickname(appUserId: string | null): Promise<string> {
  if (!appUserId) return "(не указан)";
  const r = await sbFetch(
    `/rest/v1/user_profiles?user_id=eq.${appUserId}&select=nickname&limit=1`,
  );
  const arr = await r.json();
  return arr?.[0]?.nickname || "(без ника)";
}

async function getDisplayName(appUserId: string | null): Promise<string> {
  if (!appUserId) return "(не указан)";
  const r = await sbFetch(
    `/rest/v1/app_users?id=eq.${appUserId}&select=display_name,public_id&limit=1`,
  );
  const arr = await r.json();
  if (!arr?.[0]) return "(не найден)";
  return `${arr[0].display_name} [${arr[0].public_id}]`;
}

function encodeBase64Utf8(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function chunk76(s: string): string {
  const out: string[] = [];
  for (let i = 0; i < s.length; i += 76) out.push(s.slice(i, i + 76));
  return out.join("\r\n");
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function buildHtml(args: {
  report: ContentReport;
  reporterNick: string;
  reporterDisplay: string;
  ownerNick: string;
  ownerDisplay: string;
  isCritical: boolean;
  isAutoHidden: boolean;
}): string {
  const { report, reporterNick, reporterDisplay, ownerNick, ownerDisplay, isCritical, isAutoHidden } = args;

  const categoryLabel = `${CATEGORY_RU[report.category] || report.category} (${report.category})`;
  const targetLabel = `${TARGET_TYPE_RU[report.target_type] || report.target_type} (${report.target_type})`;
  const snapshot = report.content_snapshot
    ? JSON.stringify(report.content_snapshot, null, 2)
    : "(snapshot отсутствует)";
  const comment = report.comment ? escapeHtml(report.comment) : "(пусто)";

  const banner = isCritical
    ? `<div style="background:#c0392b;color:#fff;padding:12px;border-radius:6px;margin-bottom:16px;font-size:16px;font-weight:bold">
         ⚠️ КРИТИЧНАЯ КАТЕГОРИЯ — реакция в течение 1–2 часов
       </div>`
    : "";

  const autoHideBanner = isAutoHidden
    ? `<div style="background:#f39c12;color:#fff;padding:10px;border-radius:6px;margin-bottom:16px;font-weight:bold">
         🔒 AUTO-HIDDEN: 3+ жалоб от разных пользователей. Контент скрыт автоматически.
       </div>`
    : "";

  return `<!doctype html>
<html><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#222;max-width:800px;margin:20px auto;padding:0 16px">
  ${banner}
  ${autoHideBanner}
  <h2 style="margin-top:0">Жалоба на UGC — Centry</h2>

  <table cellpadding="8" style="border-collapse:collapse;width:100%;border:1px solid #ddd">
    <tr style="background:#f8f8f8"><td style="border:1px solid #ddd"><b>Report ID</b></td>
        <td style="border:1px solid #ddd"><code>${report.id}</code></td></tr>
    <tr><td style="border:1px solid #ddd"><b>Дата</b></td>
        <td style="border:1px solid #ddd">${report.created_at}</td></tr>
    <tr style="background:#f8f8f8"><td style="border:1px solid #ddd"><b>Категория</b></td>
        <td style="border:1px solid #ddd">${escapeHtml(categoryLabel)}</td></tr>
    <tr><td style="border:1px solid #ddd"><b>Тип объекта</b></td>
        <td style="border:1px solid #ddd">${escapeHtml(targetLabel)}</td></tr>
    <tr style="background:#f8f8f8"><td style="border:1px solid #ddd"><b>ID объекта</b></td>
        <td style="border:1px solid #ddd"><code>${report.target_id}</code></td></tr>
    <tr><td style="border:1px solid #ddd"><b>Владелец контента</b></td>
        <td style="border:1px solid #ddd">${escapeHtml(ownerNick)} — ${escapeHtml(ownerDisplay)}</td></tr>
    <tr style="background:#f8f8f8"><td style="border:1px solid #ddd"><b>Жалобщик</b></td>
        <td style="border:1px solid #ddd">${escapeHtml(reporterNick)} — ${escapeHtml(reporterDisplay)}</td></tr>
    <tr><td style="border:1px solid #ddd"><b>Статус</b></td>
        <td style="border:1px solid #ddd">${report.status}</td></tr>
  </table>

  <h3>Комментарий жалобщика</h3>
  <div style="background:#f5f5f5;padding:12px;border-radius:4px;white-space:pre-wrap">${comment}</div>

  <h3>Snapshot контента (на момент жалобы)</h3>
  <pre style="background:#f5f5f5;padding:12px;border-radius:4px;overflow-x:auto;font-size:12px">${escapeHtml(snapshot)}</pre>

  <h3>Действия модератора (SQL)</h3>
  <pre style="background:#2d3436;color:#dfe6e9;padding:12px;border-radius:4px;overflow-x:auto;font-size:12px">
-- 1. Скрыть контент (помечает все жалобы по этому объекту как resolved)
INSERT INTO public.content_moderation_actions
  (report_id, target_type, target_id, action, performed_by, notes)
VALUES
  ('${report.id}', '${report.target_type}', '${report.target_id}', 'hide_content',
   (SELECT id FROM auth.users WHERE email = 'YOUR_ADMIN_EMAIL' LIMIT 1),
   'Объективно неприемлемый контент');

UPDATE public.content_reports
SET status = 'resolved', resolution = 'hide_content', resolved_at = now()
WHERE target_type = '${report.target_type}' AND target_id = '${report.target_id}'
  AND status IN ('pending','under_review');

-- 2. Отклонить жалобу (false-positive)
UPDATE public.content_reports
SET status = 'rejected', resolution = 'no_action', resolved_at = now()
WHERE id = '${report.id}';
  </pre>

  <p style="color:#7f8c8d;font-size:11px;margin-top:24px">
    Это автоматическое уведомление от Centry (Apple Guideline 1.2 compliance).<br>
    SLA: ≤ 24h для обычных категорий, ≤ 1–2h для критичных.
  </p>
</body></html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // 0. Конфиг проверяем на каждом запросе (lazy init)
  const configErr = checkConfig();
  if (configErr) {
    return new Response(`misconfigured: ${configErr}`, { status: 503 });
  }

  // 1. Auth
  const authHeader = req.headers.get("authorization") ?? "";
  const expected = `Bearer ${NOTIFY_TOKEN}`;
  if (authHeader !== expected) {
    return new Response("forbidden", { status: 403 });
  }

  // 2. Parse body
  let body: { kind?: string; id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response("invalid body", { status: 400 });
  }

  const kind = body.kind;
  const id = body.id;
  if (!kind || !id) {
    return new Response("kind and id required", { status: 400 });
  }

  // На этапе 2 поддерживаем content_report.
  // support_complaint / support_suggestion подключим вторым шагом.
  if (kind !== "content_report") {
    return new Response(JSON.stringify({ ok: true, skipped: kind }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  // 3. Достаём жалобу
  const report = await getReport(id);
  if (!report) {
    return new Response("report not found", { status: 404 });
  }

  // 4. Контекст: ники жалобщика и владельца
  const [reporterNick, reporterDisplay, ownerNick, ownerDisplay] = await Promise.all([
    getNickname(report.reporter_app_user_id),
    getDisplayName(report.reporter_app_user_id),
    getNickname(report.target_owner_app_user_id),
    getDisplayName(report.target_owner_app_user_id),
  ]);

  // 5. Маршрутизация по категории
  const isCritical = CRITICAL_CATEGORIES.has(report.category);
  const isAutoHidden = report.status === "under_review";

  const to = isCritical ? MAIL_TO_CRITICAL : MAIL_TO_REGULAR;
  const cc = isCritical && MAIL_TO_REGULAR !== MAIL_TO_CRITICAL ? [MAIL_TO_REGULAR] : undefined;

  let subjectPrefix = "[Centry Report]";
  if (report.category === "csae") subjectPrefix = "[CRITICAL: CSAE][Centry Report]";
  else if (isCritical) subjectPrefix = "[URGENT][Centry Report]";

  const autoHideTag = isAutoHidden ? " [AUTO-HIDDEN]" : "";
  const subject = `${subjectPrefix} ${report.category}: ${report.target_type}${autoHideTag}`;

  const html = buildHtml({
    report,
    reporterNick,
    reporterDisplay,
    ownerNick,
    ownerDisplay,
    isCritical,
    isAutoHidden,
  });

  // 6. Send email через Mail.ru SMTP
  const client = new SMTPClient({
    connection: {
      hostname: SMTP_HOST,
      port: SMTP_PORT,
      tls: true,
      auth: {
        username: SMTP_USER,
        password: SMTP_PASS,
      },
    },
  });

  // Кодируем HTML в base64 чтобы обойти QP-encoding denomailer'а,
  // который ломает UTF-8 multibyte символы на 76-char границе.
  const htmlBase64 = encodeBase64Utf8(html);
  // RFC 2045: base64 строки в письмах должны быть ≤ 76 символов
  const htmlBase64Chunked = chunk76(htmlBase64);

  try {
    await client.send({
      from: SMTP_FROM,
      to,
      cc,
      subject,
      mimeContent: [
        {
          mimeType: 'text/html; charset="utf-8"',
          content: htmlBase64Chunked,
          transferEncoding: "base64",
        },
      ],
    });
  } catch (err) {
    console.error("SMTP send failed:", err);
    try {
      await client.close();
    } catch {
      // ignore
    }
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }

  await client.close();

  return new Response(
    JSON.stringify({
      ok: true,
      to,
      cc,
      subject,
      report_id: report.id,
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
});
