# Android store privacy/deletion pages — October 17, 2026

This deployment publishes only public privacy and account-deletion information. Android backend features, OAuth audience/Integrity/FCM configuration and production database migrations were not deployed. Do not infer Android release readiness from this record.

## Correct production deployment

- Live source base: `16c9eb2d8be3f23175158b0721609dc27999f7bf`.
- Isolated checkout: `/private/tmp/cavecals-play-store-pages-20261017`, archived from the exact production base, then overlaid with only the two pages below. The working Android backend branch was deliberately not deployed wholesale.
- Vercel project: `cavecals`, `prj_AtiSTTEtDiqUeJMvhjDDkDuVusuI`; root directory `backend`.
- Deployment: `dpl_3Cgvtb8gSkQdhvDk7FL8bM4UwPCa`, READY; URL https://cavecals-omlm8hkgq-phils-projects-e15f8e11.vercel.app; alias https://cavecals.com.
- Previous production deployment: `dpl_4vApp1EGAhA6Me4KtFZHu5NaVJC9`.
- Production build passed in the isolated tree. Logs: `/private/tmp/cavecals-store-pages-isolated-build.log` and `/private/tmp/cavecals-store-pages-correct-deploy.log` (local, not committed).
- Visually verified public https://cavecals.com/privacy contains the Android section and deletion link, and https://cavecals.com/delete-account contains both in-app and email-request instructions. Homepage returned HTTP 200. Invalid unauthenticated account-status request bodies returned 400 `invalid_request`; this is only rejection of invalid requests, not an authentication acceptance test.
- Google Play privacy policy URL saved; deletion URL populated in the saved Data safety draft. No review submission.

| File | SHA-256 of deployed file |
| --- | --- |
| `backend/src/app/privacy/page.tsx` | `7839ce68672336195056516591c040ca9337fd0d3a738370fde79753c0121877` |
| `backend/src/app/delete-account/page.tsx` | `47f68cc44a0f530cfd8c0df52bd49b3a161cef0ce70adc324581d7574638d24a` |

## Stale-project recovery

An inherited local `.vercel` link pointed to the legacy `backend` project. The first pages-only deployment went there as `dpl_3RL8wURiK2v36k4EtWVPmEFzHeZd`. Detected this before treating it as cavecals.com production; immediately rolled that project's alias back to its previous deployment, `dpl_8JpqmCnpdCzAnsbQUkrjdh7y1Ep5` at `backend-277ipg9u8-phils-projects-e15f8e11.vercel.app`. CLI reported successful rollback and the alias was verified. No database change occurred. The correct cavecals.com alias was unaffected by that attempt. The user was informed during the work.

The correct deployment was issued from the isolated repository root with the correct project link. Do not reuse an inherited nested `backend/.vercel` link without verifying its project. Preserve these pages and current iOS production changes when later integrating the Android backend.
