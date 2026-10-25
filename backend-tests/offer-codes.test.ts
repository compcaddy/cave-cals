import test from 'node:test';
import assert from 'node:assert/strict';
import { Environment, OfferType } from '@apple/app-store-server-library';
import { purchaseOwner, redeemedOfferCode } from '../backend/src/server/apple';
import { ANDROID_ENVIRONMENT } from '../backend/src/server/android-integrity';

const ORIGINAL = '2000000123';
const install = { id: '11111111-1111-4111-8111-111111111111', environment: null, originalTransactionId: null };
const owner = { id: '22222222-2222-4222-8222-222222222222', environment: 'Production', originalTransactionId: ORIGINAL };
const rejected = (code: string) => (error: unknown) => (error as { code?: string }).code === code;

test('an offer-code purchase is claimed by the first install that reports it', () => {
  assert.equal(purchaseOwner({ originalId: ORIGINAL, installAccount: install, offerCode: true }), install.id);
  assert.equal(purchaseOwner({ originalId: ORIGINAL, installAccount: { ...install, originalTransactionId: ORIGINAL }, offerCode: true }), install.id);
});

test('a claimed offer-code purchase restores to its owner on other installs', () => {
  assert.equal(purchaseOwner({ originalId: ORIGINAL, existing: owner, installAccount: install, offerCode: true }), owner.id);
});

test('an offer-code purchase cannot replace another subscription or cross platforms', () => {
  assert.throws(() => purchaseOwner({ originalId: ORIGINAL, installAccount: { ...install, originalTransactionId: '2000000999' }, offerCode: true }), rejected('purchase_owner'));
  assert.throws(() => purchaseOwner({ originalId: ORIGINAL, installAccount: { ...install, environment: ANDROID_ENVIRONMENT }, offerCode: true }), rejected('purchase_owner'));
  assert.throws(() => purchaseOwner({ originalId: ORIGINAL, offerCode: true }), rejected('purchase_owner'));
});

test('other tokenless purchases are still refused', () => {
  assert.throws(() => purchaseOwner({ originalId: ORIGINAL, installAccount: install, offerCode: false }), rejected('purchase_owner'));
  assert.throws(() => purchaseOwner({ originalId: ORIGINAL, existing: owner, offerCode: false }), rejected('purchase_owner'));
});

test('purchases made in the app still follow their appAccountToken', () => {
  assert.equal(purchaseOwner({ token: owner.id, originalId: ORIGINAL, existing: owner, offerCode: false }), owner.id);
  assert.equal(purchaseOwner({ token: install.id, originalId: ORIGINAL, tokenAccount: install, offerCode: false }), install.id);
  assert.throws(() => purchaseOwner({ token: install.id, originalId: ORIGINAL, existing: owner, tokenAccount: install, offerCode: false }), rejected('purchase_owner'));
  assert.throws(() => purchaseOwner({ token: 'not-a-uuid', originalId: ORIGINAL, offerCode: false }), rejected('purchase_owner'));
  assert.throws(() => purchaseOwner({ token: install.id, originalId: ORIGINAL, tokenAccount: { ...install, environment: ANDROID_ENVIRONMENT }, offerCode: false }), rejected('wrong_platform'));
});

test('an offer code on the reported transaction is recognized without asking Apple', async () => {
  assert.equal(await redeemedOfferCode([{ offerType: OfferType.OFFER_CODE }], ORIGINAL, Environment.PRODUCTION), true);
});
