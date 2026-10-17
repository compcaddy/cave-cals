import { z } from 'zod';
import { createHash } from 'node:crypto';
import { ProxyAgent } from 'undici';
import { APIError, positiveInt, required } from './config';
import { consume, tomorrow, utcDay } from './rate-limit';

export const foodSearchInput = z.object({
  query: z.string().trim().min(2).max(120).refine(value => !/[\x00-\x1f\x7f]/.test(value)),
}).strict();
export interface FoodResult {
  id: string; name: string; brand?: string; calories: number; servingDescription: string; barcode?: string;
  macros?: { protein?: number; totalCarbs?: number; fiber?: number; fat?: number };
}
export const barcodeInput = z.object({ barcode: z.string().regex(/^\d{8,14}$/) }).strict();
/** FatSecret matches GTIN-13: UPC-A gains a leading zero, EAN-8 is zero-padded, a GTIN-14 drops its leading zero. */
export function gtin13(code: string): string | undefined {
  if (!/^\d{8,14}$/.test(code)) return undefined;
  if (code.length === 14) return code.startsWith('0') ? code.slice(1) : undefined;
  return code.padStart(13, '0');
}
type ObjectValue = Record<string, unknown>;
const object = (value: unknown): ObjectValue => value && typeof value === 'object' && !Array.isArray(value) ? value as ObjectValue : {};
const list = (value: unknown): unknown[] => value == null ? [] : Array.isArray(value) ? value : [value];
const string = (value: unknown) => typeof value === 'string' ? value.trim() : '';
const validCalories = (value: number) => Number.isFinite(value) && value >= 0 && value <= 100_000;
const numericID = (value: unknown) => typeof value === 'string' && /^\d+$/.test(value) ? value : undefined;
const unavailable = () => new APIError(503, 'food_search_unavailable', 'Food search is temporarily unavailable. You can still use saved foods or add calories manually.');
const nutrient = (value: unknown): number | undefined => {
  if (typeof value !== 'string' || !value.trim()) return undefined;
  const number = Number(value);
  return validCalories(number) ? number : undefined;
};
/** A Premier food (search v5, barcode v2): its default serving, with that serving's macros. */
function premierFood(food: ObjectValue): FoodResult | undefined {
  const id = numericID(food.food_id), name = string(food.food_name);
  if (!id || id === '0' || !name) return undefined;
  const servings = list(object(food.servings).serving).map(object).filter(s =>
    string(s.serving_description) && typeof s.calories === 'string' && s.calories.trim() !== '' && validCalories(Number(s.calories)));
  // Prefer the provider's default; otherwise the original portion over derived 100 g servings.
  const serving = servings.find(s => s.is_default === '1') ?? servings.find(s => s.serving_id !== '0') ?? servings[0];
  if (!serving) return undefined;
  const carbs = nutrient(serving.carbohydrate), fiber = nutrient(serving.fiber);
  return { id: `fatsecret:${id}`, name, brand: string(food.brand_name) || undefined, calories: Number(serving.calories),
    servingDescription: string(serving.serving_description),
    macros: { protein: nutrient(serving.protein), fat: nutrient(serving.fat), totalCarbs: carbs,
      // Retain total carbs even when fiber is missing or contradictory.
      fiber: fiber !== undefined && (carbs === undefined || fiber <= carbs) ? fiber : undefined } };
}
/** Barcode v2 answers with the matched food, or error 211 / food_id 0 when the barcode isn't known. */
export function normalizeBarcodeFood(payload: unknown, barcode: string): FoodResult | null {
  const root = object(payload);
  if (Number(object(root.error).code) === 211) return null;
  const food = object(root.food);
  if (!Object.keys(food).length || string(food.food_id) === '0') return null;
  const result = premierFood(food);
  if (!result) throw unavailable();
  return { ...result, barcode };
}
export function normalizeFoods(payload: unknown, premier: boolean): FoodResult[] {
  const root = object(payload);
  const container = object(premier ? root.foods_search : root.foods);
  if (!/^\d+$/.test(String(container.total_results ?? ''))) throw unavailable();
  const raw = premier ? object(container.results).food : container.food;
  if (Number(container.total_results) > 0 && raw == null) throw unavailable();
  const seen = new Set<string>();
  const foods: FoodResult[] = [];
  for (const value of list(raw)) {
    const food = object(value), id = numericID(food.food_id), name = string(food.food_name);
    if (!id || !name || seen.has(id)) continue;
    let calories: number, servingDescription: string;
    let macros: FoodResult['macros'];
    if (premier) {
      const result = premierFood(food);
      if (!result) continue;
      ({ calories, servingDescription, macros } = result);
    } else {
      // Basic returns nutrition for exactly the portion named in this description. Never assume a whole package.
      const match = /^Per\s+(.+?)\s+-\s+Calories:\s*([\d,]+(?:\.\d+)?)\s*kcal(?:\s*\||\s*$)/i.exec(string(food.food_description));
      if (!match) continue;
      servingDescription = match[1].trim(); calories = Number(match[2].replaceAll(',', ''));
      const description = string(food.food_description);
      const amount = (label: string) => nutrient(new RegExp(`(?:^|\\|)\\s*${label}:\\s*([0-9]+(?:\\.[0-9]+)?)g(?:\\s*\\||$)`, 'i').exec(description)?.[1]);
      macros = { protein: amount('Protein'), fat: amount('Fat'), totalCarbs: amount('Carbs'), fiber: undefined };
    }
    if (!servingDescription || !validCalories(calories)) continue;
    seen.add(id);
    foods.push({ id: `fatsecret:${id}`, name, brand: string(food.brand_name) || undefined, calories, servingDescription, macros });
  }
  // A malformed provider response must not masquerade as a valid empty search.
  if (Number(container.total_results) > 0 && foods.length === 0) throw unavailable();
  return foods;
}

type Options = { clientID: string; clientSecret: string; premier: boolean };
export class FatSecretClient {
  // Barcode lookups use their own token: if the account lacks the barcode scope, search keeps working.
  private tokens = new Map<string, { value: string; expires: number }>();
  private pendingTokens = new Map<string, Promise<string>>();
  private retryAfter = new Map<string, number>();
  constructor(private options: Options, private fetcher: typeof fetch = fetch,
    private reserve: () => Promise<void> = async () => {}, private now: () => number = Date.now) {}

  private async json(url: string, init: RequestInit): Promise<{ response: Response; body: ObjectValue }> {
    try {
      const response = await this.fetcher(url, { ...init, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000) });
      // Do not include upstream bodies/errors in logs or responses (they can contain credential details).
      const body = object(await response.json());
      return { response, body };
    } catch { throw unavailable(); }
  }
  private get searchScope() { return this.options.premier ? 'premier' : 'basic'; }
  private async accessToken(scope = this.searchScope): Promise<string> {
    const cached = this.tokens.get(scope);
    if (cached && cached.expires > this.now()) return cached.value;
    const pending = this.pendingTokens.get(scope);
    if (pending) return pending;
    if ((this.retryAfter.get(scope) ?? 0) > this.now()) throw unavailable();
    const request = (async () => {
      const { response, body } = await this.json('https://oauth.fatsecret.com/connect/token', {
        method: 'POST', headers: {
          Authorization: `Basic ${Buffer.from(`${this.options.clientID}:${this.options.clientSecret}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        }, body: new URLSearchParams({ grant_type: 'client_credentials', scope }).toString(),
      });
      if (!response.ok || !string(body.access_token) || !Number.isFinite(Number(body.expires_in)) || Number(body.expires_in) <= 60) throw unavailable();
      const token = { value: string(body.access_token), expires: this.now() + (Number(body.expires_in) - 60) * 1000 };
      this.tokens.set(scope, token);
      return token.value;
    })();
    this.pendingTokens.set(scope, request);
    try { return await request; }
    catch (error) { this.retryAfter.set(scope, this.now() + 30_000); throw error; }
    finally { this.pendingTokens.delete(scope); }
  }
  private dropToken(scope: string, value: string) { if (this.tokens.get(scope)?.value === value) this.tokens.delete(scope); }
  async search(query: string): Promise<{ results: FoodResult[]; cacheLifetime: number }> {
    const url = new URL(`https://platform.fatsecret.com/rest/foods/search/${this.options.premier ? 'v5' : 'v1'}`);
    url.search = new URLSearchParams({ search_expression: query, format: 'json', max_results: '25', page_number: '0',
      ...(this.options.premier ? { flag_default_serving: 'true' } : {}) }).toString();
    for (let attempt = 0; attempt < 2; attempt++) {
      const token = await this.accessToken();
      await this.reserve(); // Count every upstream search, including an authentication retry.
      const { response, body } = await this.json(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
      const code = Number(object(body.error).code);
      if ((response.status === 401 || code === 13) && attempt === 0) {
        this.dropToken(this.searchScope, token);
        continue;
      }
      if (response.status === 429 || code === 11 || code === 12) throw new APIError(429, 'food_search_busy', 'Food search is busy. Please try again later, or use your saved foods.');
      // Distinguish deployment configuration issues without exposing upstream messages or credentials.
      if (code === 21) throw new APIError(503, 'food_search_ip_denied', unavailable().message);
      if (code === 14) throw new APIError(503, 'food_search_scope_denied', unavailable().message);
      if (!response.ok || body.error) throw unavailable();
      return { results: normalizeFoods(body, this.options.premier), cacheLifetime: this.options.premier ? 3600 : 0 };
    }
    throw unavailable();
  }
  /** Premier only. Null when FatSecret doesn't know the barcode; the app then asks Open Food Facts. */
  async barcode(scanned: string): Promise<FoodResult | null> {
    const gtin = gtin13(scanned);
    if (!this.options.premier || !gtin) return null;
    const url = new URL('https://platform.fatsecret.com/rest/food/barcode/find-by-id/v2');
    url.search = new URLSearchParams({ barcode: gtin, format: 'json', flag_default_serving: 'true' }).toString();
    for (let attempt = 0; attempt < 2; attempt++) {
      const token = await this.accessToken('barcode');
      await this.reserve();
      const { response, body } = await this.json(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
      const errorCode = Number(object(body.error).code);
      if ((response.status === 401 || errorCode === 13) && attempt === 0) { this.dropToken('barcode', token); continue; }
      if (errorCode === 211) return null;
      if (response.status === 429 || errorCode === 11 || errorCode === 12) throw new APIError(429, 'food_search_busy', 'Food search is busy. Please try again later.');
      if (errorCode === 14) throw new APIError(503, 'barcode_scope_denied', unavailable().message);
      if (!response.ok || body.error) throw unavailable();
      return normalizeBarcodeFood(body, scanned);
    }
    throw unavailable();
  }
}

let client: FatSecretClient | undefined;
export function foodSearchFetch(proxyURL = process.env.FIXIE_URL, fetcher: typeof fetch = fetch): typeof fetch {
  if (!proxyURL) return fetcher;
  let proxy: ProxyAgent;
  try {
    const url = new URL(proxyURL);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Invalid proxy');
    proxy = new ProxyAgent(url.toString());
  } catch { throw unavailable(); }
  // Scope the CONNECT proxy to FatSecret. Never change the global dispatcher used by Apple/OpenAI.
  return (input, init) => {
    const options: RequestInit & { dispatcher: ProxyAgent } = { ...init, dispatcher: proxy };
    return fetcher(input, options);
  };
}
export function foodSearchClient() {
  if (!client) {
    const tier = process.env.FATSECRET_API_TIER || 'basic';
    if (!['basic', 'premier'].includes(tier)) throw unavailable();
    client = new FatSecretClient({ clientID: required('FATSECRET_CLIENT_ID'), clientSecret: required('FATSECRET_CLIENT_SECRET'), premier: tier === 'premier' }, foodSearchFetch(), async () => {
      await consume(`food-provider:${utcDay()}`, positiveInt('FOOD_SEARCH_DAILY_LIMIT', 4500), tomorrow());
    });
  }
  return client;
}
export async function limitFoodSearch(request: Request) {
  const ip = process.env.VERCEL ? request.headers.get('x-vercel-forwarded-for') || 'unknown' : 'local';
  const hash = createHash('sha256').update(`${utcDay()}:${ip}`).digest('hex');
  await consume(`food-search:${hash}:${new Date().toISOString().slice(0,16)}`, 30, tomorrow());
  await consume(`food-search-day:${hash}:${utcDay()}`, 300, tomorrow());
  await consume(`food-search-global:${utcDay()}`, positiveInt('FOOD_SEARCH_REQUEST_DAILY_LIMIT', 10000), tomorrow());
}
