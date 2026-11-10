type Settings = {
  url?: string;
  publicKey?: string;
  serviceKey?: string;
  request?: typeof fetch;
};

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const bearer = /^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i;
const maxBodyBytes = 8192;

function failure(status: number, error: string): Response {
  return Response.json({ error }, { status, headers });
}

function object(value: unknown): Record<string, unknown> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return;
  return value as Record<string, unknown>;
}

async function readDraft(req: Request) {
  const reader = req.body?.getReader();
  if (!reader) return;
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let count = 0;
  let text = "";
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      count += chunk.value.byteLength;
      if (count > maxBodyBytes) {
        await reader.cancel();
        return;
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    return object(JSON.parse(text + decoder.decode()));
  } catch {
    return;
  } finally {
    reader.releaseLock();
  }
}

function preparationFailure(status: number, result: Record<string, unknown> | undefined) {
  if (status === 401 || result?.code === "28000") return failure(401, "AUTH_REQUIRED");
  if (status === 403 || result?.code === "42501") return failure(403, "ADMIN_ACCESS_DENIED");
  if (result?.code === "P0002") return failure(404, "ACCOUNT_NOT_FOUND");
  if (result?.message === "ACCOUNT_STATUS_CHANGED") return failure(409, "ACCOUNT_STATUS_CHANGED");
  if (result?.message === "ACCOUNT_RESET_IN_PROGRESS") return failure(409, "ACCOUNT_RESET_IN_PROGRESS");
  if (result?.code === "22023") return failure(400, "INVALID_ACCOUNT_INPUT");
  return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
}

export function createResetPasswordHandler(settings: Settings) {
  const { url, publicKey, serviceKey } = settings;
  const request = settings.request ?? fetch;
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return failure(405, "METHOD_NOT_ALLOWED");
    const authorization = req.headers.get("Authorization");
    if (!authorization || !bearer.test(authorization)) return failure(401, "AUTH_REQUIRED");
    if (!url || !publicKey || !serviceKey) return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");

    const draft = await readDraft(req);
    if (!draft || Object.keys(draft).length !== 3) return failure(400, "INVALID_ACCOUNT_INPUT");
    const { account_id, expected_status, temporary_password } = draft;
    if (typeof account_id !== "string" || !uuid.test(account_id) ||
      (expected_status !== "active" && expected_status !== "locked")) {
      return failure(400, "INVALID_ACCOUNT_INPUT");
    }
    if (typeof temporary_password !== "string" || temporary_password.length < 6 ||
      !temporary_password.trim() || new TextEncoder().encode(temporary_password).byteLength > 72) {
      return failure(422, "INVALID_TEMPORARY_PASSWORD");
    }

    const accountId = account_id.toLowerCase();
    const send = (method: string, path: string, key: string, auth: string, body: Record<string, unknown>) =>
      request(`${url}${path}`, {
        method,
        headers: { apikey: key, Authorization: auth, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(12_000),
      });
    const rpc = (name: string, params: Record<string, unknown>) =>
      send("POST", `/rest/v1/rpc/${name}`, publicKey, authorization, params);

    let attemptedAuthWrite = false;
    try {
      const preflight = await rpc("admin_prepare_password_reset", {
        p_account_id: accountId,
        p_expected_status: expected_status,
      });
      const prepared = object(await preflight.json().catch(() => null));
      if (!preflight.ok) return preparationFailure(preflight.status, prepared);
      if (typeof prepared?.reset_id !== "string" || !uuid.test(prepared.reset_id) ||
        prepared.account_id !== accountId || typeof prepared.identity_code !== "string" ||
        !prepared.identity_code.trim()) {
        return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
      }

      attemptedAuthWrite = true;
      const auth = await send("PUT", `/auth/v1/admin/users/${accountId}`, serviceKey, `Bearer ${serviceKey}`, {
        password: temporary_password,
        app_metadata: { dormfix_password_reset_id: prepared.reset_id },
      });
      const authBody = object(await auth.json().catch(() => null));
      if (!auth.ok) {
        // Timeouts and upstream errors may have happened after the Auth write.
        // Leave those contexts to expire and never retry the write implicitly.
        if (auth.status >= 400 && auth.status < 500 && auth.status !== 408) {
          try {
            await rpc("admin_cancel_password_reset", { p_reset_id: prepared.reset_id });
          } catch {
            // The short-lived context will expire if cancellation is unavailable.
          }
          const code = authBody?.code ?? authBody?.error_code;
          if (code === "weak_password" || code === "validation_failed") {
            return failure(422, "INVALID_TEMPORARY_PASSWORD");
          }
          if (auth.status === 404 || code === "user_not_found") {
            return failure(404, "ACCOUNT_NOT_FOUND");
          }
          return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
        }
        return failure(502, "ACCOUNT_RESET_NOT_CONFIRMED");
      }

      const authUser = object(authBody?.user) ?? authBody;
      if (authUser?.id !== accountId) return failure(502, "ACCOUNT_RESET_NOT_CONFIRMED");
      const detail = await rpc("admin_get_account", { p_identity_code: prepared.identity_code });
      const account = object(await detail.json());
      if (!detail.ok || account?.id !== accountId ||
        account.identity_code !== prepared.identity_code || account.status !== expected_status ||
        (account.role !== "student" && account.role !== "technician") ||
        account.must_change_password !== true) {
        return failure(502, "ACCOUNT_RESET_NOT_CONFIRMED");
      }

      return Response.json({ account: {
        id: account.id,
        identity_code: account.identity_code,
        full_name: account.full_name,
        email: account.email,
        phone: account.phone,
        role: account.role,
        status: account.status,
        room_id: account.room_id,
        must_change_password: account.must_change_password,
      } }, { status: 200, headers });
    } catch {
      return attemptedAuthWrite
        ? failure(502, "ACCOUNT_RESET_NOT_CONFIRMED")
        : failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
    }
  };
}
