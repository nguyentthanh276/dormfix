import assert from 'node:assert/strict';
import test from 'node:test';
import { createAccountHandler } from './handler.ts';

const project = 'https://test.supabase.example';
const bearer = 'Bearer header.payload.signature';
const accountId = 'f36e0b56-b203-4995-9c1b-7b182732284f';
const provisionId = 'b51d2069-e7ac-4a0c-9037-5a464ef79e9a';
const roomId = '303a19be-cf3c-4830-b9fd-e4106a5fcde7';
const draft = {
  identity_code: 'STUDENT-TEST',
  full_name: 'Sinh viên kiểm thử',
  email: 'student@example.invalid',
  phone: '0900000000',
  role: 'student',
  room_id: roomId,
  temporary_password: 'temporary-test-value',
};

function invoke(handler, body = draft, authorization = bearer) {
  return handler(new Request(`${project}/functions/v1/admin-create-account`, {
    method: 'POST',
    headers: { Authorization: authorization, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }));
}

function setup(responses) {
  const calls = [];
  const handler = createAccountHandler({
    url: project,
    publicKey: 'test-public-key',
    serviceKey: 'test-service-key',
    request: async (url, options) => {
      calls.push({ url, ...options, body: JSON.parse(options.body) });
      const response = responses.shift();
      if (!response) throw new Error('Unexpected request');
      if (response instanceof Error) throw response;
      return Response.json(response.body, { status: response.status });
    },
  });
  return { handler, calls };
}

const prepared = { status: 200, body: { provision_id: provisionId, email: draft.email } };

test('non-Admin never reaches Auth Admin and receives a sanitized error', async () => {
  const { handler, calls } = setup([{ status: 403, body: { code: '42501', message: 'SQL private details' } }]);
  const response = await invoke(handler);
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'ADMIN_ACCESS_DENIED' });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /admin_prepare_account_provision$/);
  assert.equal(calls[0].headers.Authorization, bearer);
  assert.ok(!JSON.stringify(calls[0].body).includes(draft.temporary_password));
});

test('only Auth Admin receives the temporary password and the response is allowlisted', async () => {
  const { temporary_password, ...publicDraft } = draft;
  const publicAccount = { ...publicDraft, id: accountId, status: 'active', must_change_password: true };
  const { handler, calls } = setup([
    prepared,
    { status: 200, body: { id: accountId, raw_app_meta_data: { secret: 'not part of the receipt' } } },
    { status: 200, body: { ...publicAccount, unexpected: temporary_password } },
  ]);
  const response = await invoke(handler);
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { account: publicAccount });
  assert.equal(calls.length, 3);
  assert.equal(calls[0].headers.Authorization, bearer);
  assert.ok(!JSON.stringify(calls[0].body).includes(temporary_password));
  assert.match(calls[1].url, /auth\/v1\/admin\/users$/);
  assert.deepEqual(calls[1].body, {
    email: draft.email, password: temporary_password, email_confirm: true,
    app_metadata: { dormfix_provision_id: provisionId },
  });
  assert.equal(calls[2].headers.Authorization, bearer);
  assert.deepEqual(calls[2].body, { p_identity_code: draft.identity_code });
});

test('definite duplicates discard the nonce but an unknown write is never retried', async () => {
  const duplicate = setup([
    prepared,
    { status: 422, body: { code: 'email_exists' } },
    { status: 200, body: true },
  ]);
  const rejected = await invoke(duplicate.handler);
  assert.equal(rejected.status, 409);
  assert.deepEqual(await rejected.json(), { error: 'ACCOUNT_EMAIL_ALREADY_EXISTS' });
  assert.deepEqual(duplicate.calls[2].body, { p_provision_id: provisionId });

  const unknown = setup([prepared, new Error('Request timed out')]);
  const uncertain = await invoke(unknown.handler);
  assert.equal(uncertain.status, 502);
  assert.deepEqual(await uncertain.json(), { error: 'ACCOUNT_CREATE_NOT_CONFIRMED' });
  assert.equal(unknown.calls.length, 2);
});

test('rejects anonymous calls, role injection and oversized UTF-8 passwords before any backend call', async () => {
  const { handler, calls } = setup([]);
  assert.equal((await invoke(handler, draft, '')).status, 401);
  assert.equal((await invoke(handler, { ...draft, role: 'admin' })).status, 400);
  assert.equal((await invoke(handler, { ...draft, temporary_password: '      ' })).status, 422);
  assert.equal((await invoke(handler, { ...draft, temporary_password: 'é'.repeat(37) })).status, 422);
  assert.equal(calls.length, 0);
});
