import assert from "node:assert/strict";
import test from "node:test";
import { createResetPasswordHandler } from "./handler.ts";

const project = "https://test.supabase.example";
const bearer = "Bearer header.payload.signature";
const accountId = "f36e0b56-b203-4995-9c1b-7b182732284f";
const resetId = "b51d2069-e7ac-4a0c-9037-5a464ef79e9a";
const identityCode = "TECH-TEST";
const draft = {
  account_id: accountId,
  expected_status: "locked",
  temporary_password: "temporary-test-value",
};
const prepared = { status: 200, body: {
  reset_id: resetId,
  account_id: accountId,
  identity_code: identityCode,
} };
const saved = { status: 200, body: { id: accountId } };
const profile = {
  id: accountId,
  identity_code: identityCode,
  full_name: "Kỹ thuật viên kiểm thử",
  email: "tech@example.invalid",
  phone: "0900000000",
  role: "technician",
  status: "locked",
  room_id: null,
  must_change_password: true,
};

function invoke(handler, body = draft, authorization = bearer) {
  return handler(new Request(`${project}/functions/v1/admin-reset-account-password`, {
    method: "POST",
    headers: { Authorization: authorization, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }));
}

function setup(responses) {
  const calls = [];
  const handler = createResetPasswordHandler({
    url: project,
    publicKey: "test-public-key",
    serviceKey: "test-service-key",
    request: async (url, options) => {
      calls.push({ url, ...options, body: JSON.parse(options.body) });
      const response = responses.shift();
      if (!response) throw new Error("Unexpected request");
      if (response instanceof Error) throw response;
      return Response.json(response.body, { status: response.status });
    },
  });
  return { handler, calls };
}

test("reset preserves locked status and sends the temporary password only to Auth Admin", async () => {
  const { handler, calls } = setup([
    prepared,
    { status: 200, body: { user: { id: accountId }, extra: draft.temporary_password } },
    { status: 200, body: { ...profile, unexpected: draft.temporary_password } },
  ]);
  const response = await invoke(handler);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { account: profile });
  assert.deepEqual(calls.map(({ url, method, headers, body }) => ({ url, method, headers, body })), [
    {
      url: `${project}/rest/v1/rpc/admin_prepare_password_reset`,
      method: "POST",
      headers: { apikey: "test-public-key", Authorization: bearer, "Content-Type": "application/json" },
      body: { p_account_id: accountId, p_expected_status: "locked" },
    },
    {
      url: `${project}/auth/v1/admin/users/${accountId}`,
      method: "PUT",
      headers: {
        apikey: "test-service-key",
        Authorization: "Bearer test-service-key",
        "Content-Type": "application/json",
      },
      body: {
        password: draft.temporary_password,
        app_metadata: { dormfix_password_reset_id: resetId },
      },
    },
    {
      url: `${project}/rest/v1/rpc/admin_get_account`,
      method: "POST",
      headers: { apikey: "test-public-key", Authorization: bearer, "Content-Type": "application/json" },
      body: { p_identity_code: identityCode },
    },
  ]);
});

test("permission and precondition failures never reach Auth Admin and only return allowed codes", async () => {
  const failures = [
    [{ status: 403, body: { code: "42501", message: "private details" } }, 403, "ADMIN_ACCESS_DENIED"],
    [{ status: 400, body: { code: "P0001", message: "ACCOUNT_STATUS_CHANGED" } }, 409, "ACCOUNT_STATUS_CHANGED"],
    [{ status: 400, body: { code: "P0001", message: "ACCOUNT_RESET_IN_PROGRESS" } }, 409, "ACCOUNT_RESET_IN_PROGRESS"],
    [{ status: 404, body: { code: "P0002", message: "private details" } }, 404, "ACCOUNT_NOT_FOUND"],
    [{ status: 404, body: { code: "PGRST202", message: "private details" } }, 503, "ACCOUNT_SERVICE_UNAVAILABLE"],
  ];
  for (const [preflight, status, error] of failures) {
    const { handler, calls } = setup([preflight]);
    const response = await invoke(handler);
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { error });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].headers.Authorization, bearer);
  }
});

test("definite validation failures cancel their context, but unknown writes are never retried or cancelled", async () => {
  const definite = setup([
    prepared,
    { status: 422, body: { code: "weak_password", message: draft.temporary_password } },
    { status: 200, body: true },
  ]);
  const rejected = await invoke(definite.handler);
  assert.equal(rejected.status, 422);
  assert.deepEqual(await rejected.json(), { error: "INVALID_TEMPORARY_PASSWORD" });
  assert.equal(definite.calls.length, 3);
  assert.match(definite.calls[2].url, /admin_cancel_password_reset$/);
  assert.equal(definite.calls[2].headers.Authorization, bearer);
  assert.deepEqual(definite.calls[2].body, { p_reset_id: resetId });

  for (const problem of [
    new Error("Request timed out"),
    { status: 408, body: {} },
    { status: 500, body: { message: "private details" } },
  ]) {
    const uncertain = setup([prepared, problem]);
    const response = await invoke(uncertain.handler);
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: "ACCOUNT_RESET_NOT_CONFIRMED" });
    assert.equal(uncertain.calls.length, 2);
  }
});

test("a wrong Auth receipt or a missing password-change gate never reports success", async () => {
  const wrongAccount = setup([prepared, { status: 200, body: { id: resetId } }]);
  assert.equal((await invoke(wrongAccount.handler)).status, 502);
  assert.equal(wrongAccount.calls.length, 2);

  const missingGate = setup([
    prepared,
    saved,
    { status: 200, body: { ...profile, must_change_password: false } },
  ]);
  const response = await invoke(missingGate.handler);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "ACCOUNT_RESET_NOT_CONFIRMED" });
  assert.equal(missingGate.calls.length, 3);
});

test("malformed, anonymous and oversized inputs cannot make any backend call", async () => {
  const { handler, calls } = setup([]);
  assert.equal((await invoke(handler, draft, "")).status, 401);
  assert.equal((await invoke(handler, { ...draft, account_id: "not-an-id" })).status, 400);
  assert.equal((await invoke(handler, { ...draft, expected_status: "revoked" })).status, 400);
  assert.equal((await invoke(handler, { ...draft, temporary_password: "      " })).status, 422);
  assert.equal((await invoke(handler, { ...draft, temporary_password: "abc12" })).status, 422);
  assert.equal((await invoke(handler, { ...draft, temporary_password: "é".repeat(37) })).status, 422);
  assert.equal((await invoke(handler, { ...draft, temporary_password: "a".repeat(8193) })).status, 400);
  assert.equal(calls.length, 0);
});
