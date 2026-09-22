import test from 'node:test';
import assert from 'node:assert/strict';
import { FatSecretClient, normalizeFoods, foodSearchInput } from '../backend/src/server/food-search';
import { APIError } from '../backend/src/server/config';
import { api } from '../backend/src/server/api';
const options = { clientID: 'fixture-id', clientSecret: 'fixture-secret', premier: false };
const food = { food_id: '123', food_name: 'So-Cal Sandwich', brand_name: 'Urbane Cafe', food_description: 'Per 1 sandwich - Calories: 800kcal | Fat: 36.00g | Carbs: 45.00g' };
const result = { foods: { total_results: '1', food } };
const json = (body: unknown, status = 200) => Response.json(body, { status });
const fetcher = (fn: (url: string, init?: RequestInit) => Promise<Response>) => fn as typeof fetch;
const token = () => json({ access_token: 'fixture-token', expires_in: 86400 });

test('Basic preserves restaurant, calorie portion, zero calories, and single-object response', () => {
  assert.deepEqual(normalizeFoods(result, false), [{ id: 'fatsecret:123', name: 'So-Cal Sandwich', brand: 'Urbane Cafe', calories: 800, servingDescription: '1 sandwich' }]);
  assert.equal(normalizeFoods({ foods: { total_results: '1', food: { ...food, food_description: 'Per 100 g - Calories: 0kcal | Fat: 0g' } } }, false)[0].calories, 0);
  assert.deepEqual(normalizeFoods({ foods: { total_results: '0' } }, false), []);
  assert.equal(normalizeFoods({ foods: { total_results: '2', food: [food, food] } }, false).length, 1);
  assert.throws(() => normalizeFoods({}, false));
  assert.throws(() => normalizeFoods({ foods: { total_results: '1', food: { ...food, food_description: 'unknown calories' } } }, false));
});
test('Premier selects the default portion and retains its calories without multiplying units', () => {
  const servings = [{ serving_id: '0', serving_description: '100 g', calories: '200' }, { serving_id: '55', serving_description: '2 sandwiches', number_of_units: '2', calories: '800', is_default: '1' }];
  const response = { foods_search: { total_results: '1', results: { food: { ...food, servings: { serving: servings } } } } };
  const normalized = normalizeFoods(response, true)[0];
  assert.equal(normalized.calories, 800); assert.equal(normalized.servingDescription, '2 sandwiches');
  delete (servings[1] as Record<string, unknown>).is_default;
  assert.equal(normalizeFoods(response, true)[0].servingDescription, '2 sandwiches');
});
test('token exchange is server-side and concurrent searches share one refresh', async () => {
  let tokens = 0, searches = 0, reservations = 0;
  const client = new FatSecretClient(options, fetcher(async (url, init) => {
    assert.equal(init?.cache, 'no-store'); assert.equal(init?.redirect, 'error'); assert.ok(init?.signal);
    if (url.includes('/connect/token')) {
      tokens++; assert.equal(new Headers(init?.headers).get('Authorization'), `Basic ${Buffer.from('fixture-id:fixture-secret').toString('base64')}`);
      assert.equal(new URLSearchParams(String(init?.body)).get('scope'), 'basic'); return token();
    }
    searches++; assert.equal(new URL(url).pathname, '/rest/foods/search/v1');
    assert.equal(new URL(url).searchParams.get('search_expression'), 'Urbane Cafe & salad');
    assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer fixture-token');
    assert.ok(!url.includes('fixture-secret')); return json(result);
  }), async () => { reservations++; });
  const pages = await Promise.all([client.search('Urbane Cafe & salad'), client.search('Urbane Cafe & salad')]);
  assert.equal(tokens, 1); assert.equal(searches, 2); assert.equal(reservations, 2); assert.equal(pages[0].cacheLifetime, 0);
});
test('expired token is renewed and upstream 401 is retried only once', async () => {
  let now = 1000, tokens = 0, searches = 0;
  const client = new FatSecretClient(options, fetcher(async url => {
    if (url.includes('/connect/token')) { tokens++; return token(); }
    searches++; return searches <= 2 ? json({ error: { code: 13 } }) : json(result);
  }), async () => {}, () => now);
  await assert.rejects(client.search('sandwich'), APIError);
  assert.equal(tokens, 2); assert.equal(searches, 2);
  now += 86400 * 1000; await client.search('sandwich'); assert.equal(tokens, 3);
});
test('provider quota errors, HTTP-200 API errors, malformed replies, and network failures never become empty results', async () => {
  for (const response of [() => json({ error: { code: 11, message: 'private detail' } }), () => json({ error: { code: 8 } }), () => json({}), () => new Response('bad gateway', { status: 502 })]) {
    const client = new FatSecretClient(options, fetcher(async url => url.includes('/connect/token') ? token() : response()));
    await assert.rejects(client.search('food'), (e: unknown) => e instanceof APIError && !e.message.includes('private detail'));
  }
  let calls = 0;
  const client = new FatSecretClient(options, fetcher(async () => { calls++; throw new Error('fixture-secret'); }));
  await assert.rejects(client.search('food'), APIError); await assert.rejects(client.search('food'), APIError);
  assert.equal(calls, 1, 'failed token requests back off instead of hammering OAuth');
});
test('Premier uses v5 and offers a bounded positive-result cache lifetime', async () => {
  const client = new FatSecretClient({ ...options, premier: true }, fetcher(async (url, init) => {
    if (url.includes('/connect/token')) { assert.equal(new URLSearchParams(String(init?.body)).get('scope'), 'premier'); return token(); }
    assert.equal(new URL(url).pathname, '/rest/foods/search/v5'); assert.equal(new URL(url).searchParams.get('flag_default_serving'), 'true');
    return json({ foods_search: { total_results: '0' } });
  }));
  assert.deepEqual(await client.search('no matches'), { results: [], cacheLifetime: 3600 });
});
test('quota reservation rejects before issuing a provider search', async () => {
  let searches = 0;
  const client = new FatSecretClient(options, fetcher(async url => {
    if (url.includes('/connect/token')) return token(); searches++; return json(result);
  }), async () => { throw new APIError(429, 'usage_limit', 'Limit reached'); });
  await assert.rejects(client.search('food'), (e: unknown) => e instanceof APIError && e.status === 429);
  assert.equal(searches, 0);
});
test('IP and plan restrictions return safe actionable categories without upstream details', async () => {
  for (const [code, expected] of [[21, 'food_search_ip_denied'], [14, 'food_search_scope_denied']] as const) {
    const client = new FatSecretClient(options, fetcher(async url => url.includes('/connect/token') ? token() : json({ error: { code, message: 'private account detail' } })));
    await assert.rejects(client.search('Urbane Cafe'), (e: unknown) => e instanceof APIError && e.status === 503 && e.code === expected && !e.message.includes('private account detail'));
  }
});
test('invalid and oversized search requests are rejected before credentials, database or provider access', async () => {
  for (const query of ['', 'a', 'x'.repeat(121), 'food\nsecret']) assert.equal(foodSearchInput.safeParse({ query }).success, false);
  for (const [body, status] of [[JSON.stringify({ query: 'a' }), 400], ['x'.repeat(1025), 413], ['not json', 400]] as const) {
    const response = await api(new Request('https://example.com/api/v1/foods/search', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body }), 'foods/search');
    assert.equal(response.status, status); assert.equal(response.headers.get('cache-control'), 'no-store');
  }
});

test('optional Fixie proxy is scoped to FatSecret and rejects invalid configuration without leaking it', async () => {
  const { foodSearchFetch } = await import('../backend/src/server/food-search');
  let options: RequestInit & { dispatcher?: { close: () => Promise<void> } } = {};
  const fetcher: typeof fetch = async (_url, init) => { options = init ?? {}; return Response.json({}); };
  assert.equal(foodSearchFetch('', fetcher), fetcher);
  const proxied = foodSearchFetch('http://fixture-user:fixture-password@localhost:1234', fetcher);
  await proxied('https://platform.fatsecret.com/rest/foods/search/v1', { headers: { Authorization: 'Bearer fixture' } });
  assert.ok(options.dispatcher);
  assert.deepEqual(options.headers, { Authorization: 'Bearer fixture' });
  await options.dispatcher.close();
  assert.throws(() => foodSearchFetch('invalid-secret-value', fetcher), (error: unknown) => !String(error).includes('invalid-secret-value'));
});
