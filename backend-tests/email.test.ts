import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { compose, unsubscribeToken, unsubscribeURL, validUnsubscribe } from '../backend/src/server/email';
import { verifiedEmail } from '../backend/src/server/clan-auth';

const key = randomBytes(32);
const person = '6f1c2a4e-1b2c-4d3e-8f90-123456789abc';

test('unsubscribe links only work for the person they were made for', () => {
  const token = unsubscribeToken(person, key);
  assert.ok(validUnsubscribe(person, token, key));
  assert.ok(!validUnsubscribe('00000000-0000-4000-8000-000000000000', token, key));
  assert.ok(!validUnsubscribe(person, token, randomBytes(32)));
  assert.ok(!validUnsubscribe(person, token.slice(1), key));
  assert.match(unsubscribeURL(person, key), /^https:\/\/cavecals\.com\/unsubscribe\?p=6f1c2a4e-.*&t=[A-Za-z0-9_-]{32}$/);
});

test('every email has the unsubscribe link and postal address, and the HTML escapes the text', () => {
  const { text, html } = compose('Hi <cavemen>!\n\nRead more at https://cavecals.com/news', 'https://cavecals.com/unsubscribe?p=x&t=y', '123 Main St, Austin, TX 78701');
  assert.ok(text.includes('Unsubscribe: https://cavecals.com/unsubscribe?p=x&t=y'));
  assert.ok(text.includes('123 Main St, Austin, TX 78701'));
  assert.ok(html.includes('&lt;cavemen&gt;'));
  assert.ok(!html.includes('<cavemen>'));
  assert.ok(html.includes('<a href="https://cavecals.com/news"'));
  assert.equal((html.match(/<p style="margin:0 0 16px">/g) ?? []).length, 2);
});

test('only emails the provider verified are kept; Apple relay addresses are marked private', () => {
  assert.deepEqual(verifiedEmail({ iss: '', aud: '', sub: 's', exp: 0, email: 'Phil@Example.com', email_verified: true }), { email: 'phil@example.com', emailPrivate: false });
  assert.deepEqual(verifiedEmail({ iss: '', aud: '', sub: 's', exp: 0, email: 'ab12@privaterelay.appleid.com', email_verified: 'true', is_private_email: 'true' }), { email: 'ab12@privaterelay.appleid.com', emailPrivate: true });
  assert.equal(verifiedEmail({ iss: '', aud: '', sub: 's', exp: 0, email: 'x@example.com', email_verified: false }), null);
  assert.equal(verifiedEmail({ iss: '', aud: '', sub: 's', exp: 0 }), null);
});
