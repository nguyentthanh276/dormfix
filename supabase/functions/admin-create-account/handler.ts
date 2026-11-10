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
  if (result?.code === "23505" && result.message === "ACCOUNT_EMAIL_ALREADY_EXISTS") {
    return failure(409, "ACCOUNT_EMAIL_ALREADY_EXISTS");
  }
  if (result?.code === "23505" && result.message === "ACCOUNT_IDENTITY_ALREADY_EXISTS") {
    return failure(409, "ACCOUNT_IDENTITY_ALREADY_EXISTS");
  }
  if (result?.code === "22023" && result.message === "ACTIVE_STUDENT_ROOM_REQUIRED") {
    return failure(409, "ACTIVE_ROOM_REQUIRED");
  }
  if (result?.code === "22023" && result.message === "INVALID_ACCOUNT_PHONE") {
    return failure(400, "INVALID_ACCOUNT_PHONE");
  }
  if (result?.code === "22023") return failure(400, "INVALID_ACCOUNT_INPUT");
  return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
}

export function createAccountHandler(settings: Settings) {
  const request = settings.request ?? fetch;
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return failure(405, "METHOD_NOT_ALLOWED");
    const authorization = req.headers.get("Authorization");
    if (!authorization || !bearer.test(authorization)) return failure(401, "AUTH_REQUIRED");
    if (!settings.url || !settings.publicKey || !settings.serviceKey) {
      return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
    }

    const draft = await readDraft(req);
    if (!draft || Object.keys(draft).length !== 7) return failure(400, "INVALID_ACCOUNT_INPUT");
    const { identity_code, full_name, email, phone, role, room_id, temporary_password } = draft;
    if (typeof identity_code !== "string" || typeof full_name !== "string" ||
      typeof email !== "string" || typeof phone !== "string" ||
      (role !== "student" && role !== "technician") ||
      (role === "student" && (typeof room_id !== "string" || !uuid.test(room_id))) ||
      (role === "technician" && room_id !== null)) {
      return failure(400, "INVALID_ACCOUNT_INPUT");
    }
    if (typeof temporary_password !== "string" || temporary_password.length < 6 ||
      !temporary_password.trim() ||
      new TextEncoder().encode(temporary_password).byteLength > 72) {
      return failure(422, "INVALID_TEMPORARY_PASSWORD");
    }

    const post = (path: string, key: string, auth: string, body: Record<string, unknown>) =>
      request(`${settings.url}${path}`, {
        method: "POST",
        headers: { apikey: key, Authorization: auth, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(12_000),
      });
    const rpc = (name: string, params: Record<string, unknown>) =>
      post(`/rest/v1/rpc/${name}`, settings.publicKey!, authorization, params);

    let attemptedAuthWrite = false;
    try {
      // PostgREST validates the original user JWT. The preparation RPC checks
      // the live Admin profile before it returns a one-shot, private nonce.
      const preflight = await rpc("admin_prepare_account_provision", {
        p_identity_code: identity_code,
        p_full_name: full_name,
        p_email: email,
        p_phone: phone,
        p_role: role,
        p_room_id: room_id,
      });
      const prepared = object(await preflight.json());
      if (!preflight.ok) return preparationFailure(preflight.status, prepared);
      if (typeof prepared?.provision_id !== "string" || !uuid.test(prepared.provision_id) ||
        typeof prepared.email !== "string" || prepared.email !== email.trim().toLowerCase()) {
        return failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
      }

      attemptedAuthWrite = true;
      const auth = await post("/auth/v1/admin/users", settings.serviceKey, `Bearer ${settings.serviceKey}`, {
        email: prepared.email,
        password: temporary_password,
        email_confirm: true,
        app_metadata: { dormfix_provision_id: prepared.provision_id },
      });
      const authBody = object(await auth.json());
      if (!auth.ok) {
        if (auth.status < 500) {
          try {
            await rpc("admin_cancel_account_provision", { p_provision_id: prepared.provision_id });
          } catch {
            // Expired contexts are discarded by the database on the next prepare.
          }
          const code = authBody?.code ?? authBody?.error_code;
          if (code === "email_exists" || code === "user_already_exists") {
            return failure(409, "ACCOUNT_EMAIL_ALREADY_EXISTS");
          }
          if (code === "weak_password" || code === "validation_failed") {
            return failure(422, "INVALID_TEMPORARY_PASSWORD");
          }
        }
        return failure(502, "ACCOUNT_CREATE_NOT_CONFIRMED");
      }

      const authUser = object(authBody?.user) ?? authBody;
      if (typeof authUser?.id !== "string" || !uuid.test(authUser.id)) {
        return failure(502, "ACCOUNT_CREATE_NOT_CONFIRMED");
      }
      const detail = await rpc("admin_get_account", { p_identity_code: identity_code });
      const account = object(await detail.json());
      if (!detail.ok || account?.id !== authUser.id || account.email !== prepared.email ||
        account.role !== role || account.must_change_password !== true) {
        return failure(502, "ACCOUNT_CREATE_NOT_CONFIRMED");
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
      } }, { status: 201, headers });
    } catch {
      return attemptedAuthWrite
        ? failure(502, "ACCOUNT_CREATE_NOT_CONFIRMED")
        : failure(503, "ACCOUNT_SERVICE_UNAVAILABLE");
    }
  };
}
