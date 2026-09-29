import webpush from "npm:web-push";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("HAMA_SUPABASE_SECRET_KEY")!;
const vapidPublicKey = Deno.env.get("HAMA_VAPID_PUBLIC_KEY")!;
const vapidPrivateKey = Deno.env.get("HAMA_VAPID_PRIVATE_KEY")!;
const vapidSubject = Deno.env.get("HAMA_VAPID_SUBJECT") || "mailto:admin@hamaholding.com";
const webhookSecret = Deno.env.get("HAMA_WEBHOOK_SECRET")!;

webpush.setVapidDetails(
  vapidSubject,
  vapidPublicKey,
  vapidPrivateKey,
);

const headers = {
  "Content-Type": "application/json",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers,
  });
}

async function supabaseFetch(path: string, init: RequestInit = {}) {
  return fetch(`${supabaseUrl}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  if (!webhookSecret || req.headers.get("x-hama-webhook-secret") !== webhookSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const payload = await req.json();
    const record = payload?.record;

    if (!record?.user_id) {
      return json({ ok: true, skipped: "notification has no user_id" });
    }

    const userId = String(record.user_id);

    const subResponse = await supabaseFetch(
      `user_push_subscriptions?select=id,endpoint,p256dh,auth&user_id=eq.${encodeURIComponent(userId)}&active=eq.true`,
    );

    if (!subResponse.ok) {
      const detail = await subResponse.text();
      throw new Error(`Could not load push subscriptions: ${detail}`);
    }

    const subscriptions = await subResponse.json();

    const title = String(record.title || "Hama Work");
    const body = String(record.body || "You have a new Hama Work notification.");
    const targetType = record.target_type ? String(record.target_type) : null;
    const targetId = record.target_id ? String(record.target_id) : null;

    const pushPayload = JSON.stringify({
      title,
      body,
      tag: `hama-${record.id}`,
      data: {
        notificationId: String(record.id),
        targetType,
        targetId,
      },
    });

    let sent = 0;
    let removed = 0;

    for (const subscription of subscriptions) {
      try {
        await webpush.sendNotification(
          {
            endpoint: subscription.endpoint,
            keys: {
              p256dh: subscription.p256dh,
              auth: subscription.auth,
            },
          },
          pushPayload,
          {
            TTL: 60 * 60 * 24,
          },
        );
        sent++;
      } catch (error) {
        const statusCode = (error as { statusCode?: number })?.statusCode;

        // Browser subscriptions that return 404/410 are expired/unusable.
        if (statusCode === 404 || statusCode === 410) {
          await supabaseFetch(
            `user_push_subscriptions?id=eq.${encodeURIComponent(String(subscription.id))}`,
            {
              method: "PATCH",
              body: JSON.stringify({
                active: false,
                updated_at: new Date().toISOString(),
              }),
            },
          );
          removed++;
        } else {
          console.error("Push delivery failed", error);
        }
      }
    }

    return json({
      ok: true,
      notificationId: record.id,
      sent,
      removed,
    });
  } catch (error) {
    console.error(error);
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
