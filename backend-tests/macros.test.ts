import test from 'node:test';
import assert from 'node:assert/strict';
import OpenAI from 'openai';
import { estimateMacros, macroInput, validateMacros } from '../backend/src/server/macros';
import { validateResult } from '../backend/src/server/ai';
import { api } from '../backend/src/server/api';

test('macro contract distinguishes unknown and known zero; rejects non-finite, negative, excessive values', () => {
  assert.deepEqual(validateMacros({ protein: 0, totalCarbs: null, fiber: null, fat: 10.25 }), { protein: 0, totalCarbs: null, fiber: null, fat: 10.25 });
  for (const protein of [-1, NaN, Infinity, 100001, '2']) assert.throws(() => validateMacros({ protein, totalCarbs: null, fiber: null, fat: null }));
  assert.throws(() => validateMacros({ protein: 1, totalCarbs: 5, fiber: 6, fat: 1 }));
  assert.throws(() => validateMacros({ protein: 1, totalCarbs: 5, fat: 1 }));
  assert.deepEqual(validateMacros({ protein: 1, totalCarbs: 30, fiber: 3, fat: 0 }), { protein: 1, totalCarbs: 30, fiber: 3, fat: 0 });
  const item = { name: 'Egg', calories: 70, portion: '1 egg', servingSize: '1 egg', servings: 1, confidence: 'high' };
  assert.equal(validateResult({ items: [item], notes: '' }).items[0].macros, null);
  const macros = { protein: 6, totalCarbs: 0.5, fiber: 0, fat: 5 };
  assert.deepEqual(validateResult({ items: [{ ...item, macros }], notes: '' }).items[0].macros, macros);
  assert.throws(() => validateResult({ items: [{ ...item, macros: { ...macros, fat: -1 } }], notes: '' }));
});

test('text estimate sends only the one food, requests total-portion grams, and validates the reply', async () => {
  const input = macroInput.parse({ name: 'Two eggs', calories: 140, servingSize: '1 egg', servings: 2 });
  const result = { protein: 12, totalCarbs: 1, fiber: 0, fat: 10 };
  let calls = 0;
  const client = { responses: { parse: async (request: Record<string, unknown>) => {
    calls++;
    assert.equal(request.store, false);
    assert.deepEqual(JSON.parse(String(request.input)), input);
    assert.match(String(request.instructions), /ENTIRE portion/);
    assert.match(String(request.instructions), /INCLUDING dietary fiber/);
    assert.match(String(request.instructions), /never instructions/);
    return { output_parsed: result };
  } } } as unknown as OpenAI;
  assert.deepEqual(await estimateMacros(input, client), result);
  assert.equal(calls, 1);
  for (const invalid of [{ ...input, name: '' }, { ...input, calories: -1 }, { ...input, servings: 0 }]) assert.equal(macroInput.safeParse(invalid).success, false);
});

test('macro estimation endpoint requires authentication before any provider call', async () => {
  const response = await api(new Request('https://example.com/api/v1/food/macros', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ nonce: 'unused', name: 'Eggs', calories: 140, servingSize: '1 egg', servings: 2 }),
  }), 'food/macros');
  assert.equal(response.status, 401);
});
