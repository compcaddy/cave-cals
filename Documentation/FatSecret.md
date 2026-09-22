# FatSecret restaurant and food search

Implemented September 21, 2026. Native changes require a new iOS build; deploying the backend does not update the installed App Store app.

## Configuration

Production Vercel project: `cavecals` (`prj_AtiSTTEtDiqUeJMvhjDDkDuVusuI`), root directory `backend`, public URL `https://cavecals.vercel.app`. Deploy from the repository root. The nested `backend/.vercel` association points to a different project and must not be used for production deployments.

Server-only environment variables:

| Variable | Purpose |
| --- | --- |
| `FATSECRET_CLIENT_ID` | OAuth client ID |
| `FATSECRET_CLIENT_SECRET` | OAuth client secret; never use `NEXT_PUBLIC_` or embed in Swift |
| `FATSECRET_API_TIER` | `basic` by default. Set `premier` after FatSecret enables Premier or Premier Free. |
| `FOOD_SEARCH_DAILY_LIMIT` | Provider search attempts across all instances, default 4,500 per UTC day (below Basic's published 5,000/day). Raise to match the approved plan. |
| `FOOD_SEARCH_REQUEST_DAILY_LIMIT` | Incoming search requests across all instances, default 10,000 per UTC day. |

The ignored `.env.fatsecret.local` file is a credential handoff file only, not loaded by Next.js automatically. Move its values into the relevant server environment without printing them. Redeploy after changing Vercel environment variables.

FatSecret's OAuth guide requires allowed server egress IPs. If the account enforces this, configure stable egress (for example Vercel Static IPs) and allowlist only the assigned IPs in FatSecret. An arbitrary observed serverless IP is not a reliable allowlist. Do not enable paid infrastructure or broad IP ranges automatically. Verify from the deployed function, not just a local computer.

## Request flow and reliability

`POST /api/v1/foods/search` accepts `{ "query": "Urbane Cafe" }`, with 2–120 characters and a 1 KB request-body limit. It is public/free, separate from the App Attest and subscription gates protecting AI actions. It returns `{ results, cacheLifetime }`. Each result contains an ID, food name, optional brand, calories, and the exact serving description.

- Basic: `GET /rest/foods/search/v1`, parse the documented calorie/portion description.
- Premier: `GET /rest/foods/search/v5`, request default-serving flags and select the default or original serving, avoiding a synthetic 100 g portion when possible.
- OAuth client credentials flow uses HTTPS Basic authentication. Tokens are reused until one minute before expiry. Concurrent calls share refreshes; failed token requests back off for 30 seconds per instance.
- Upstream requests have eight-second timeouts, no HTTP caching, and no redirects. Invalid-token failures refresh once. Quota, malformed data, network and provider errors remain failures rather than empty search results.
- Shared Neon counters bound each IP to 30 requests/minute and 300/day, with separate global incoming-request and provider-attempt limits. Daily-salted IP hashes are stored; query text, credentials and raw upstream error bodies are not logged or stored by application code. Existing cleanup expires counters; no schema migration is needed.
- Basic result caching is disabled. Premier positive results may be cached locally for one hour. Empty results/errors are never cached. Expired entries are pruned on search/reopen and a request identity guard prevents older responses from replacing newer ones.
- Barcode lookup continues to use Open Food Facts. Manual logging, local common foods, history and meals work without this endpoint.

## Attribution and rollout

Search screens, the personal area and the website link to FatSecret. Privacy and terms pages explain the additional provider. Before shipping the native update, include the required `Powered by fatsecret nutrition API` attribution and `www.fatsecret.com` in the App Store description. Confirm the account's permitted caching/storage terms when finalizing the commercial plan, including user-created diary snapshots and saved meals; this implementation does not build a permanent provider search catalog.

## Verification

- Backend unit tests cover Basic/Premier mapping, single/array/empty/malformed responses, calorie portions, duplicate IDs, OAuth reuse/expiry, authentication retry, quota errors, network failures, redaction, and input bounds.
- Development-database integration exercises the free search route and shared limits without bypassing existing paid-feature authentication tests. Provider responses in these tests are fixtures.
- Native tests cover the HTTP contract, restaurant identity, rate-limit errors, empty-result retries, cache persistence/expiry, no-cache Basic responses, and overlapping searches.
- Live FatSecret credentials, Vercel egress, restaurant coverage and deployment smoke checks must be verified separately; fixture tests are not evidence of live provider access.

## Deployment evidence — September 21, 2026

- Production deployment `dpl_47GsvDJqf7dn5tn5LPVAw4oJ8kPw` is READY and aliased to `https://cavecals.vercel.app`.
- Production `/`, `/privacy`, and `/terms` return 200; `/test` remains 404; unsigned `/api/v1/account/status` remains 401.
- Initial deployment: invalid food queries returned 400 and a valid `Urbane Cafe` query returned 503 `not_configured` before credentials were supplied. See the follow-up below for current status.
- TypeScript typecheck, optimized local and Vercel builds, 20 backend unit tests, and 8 development-database integration tests passed.
- 42 native unit tests passed across the main suite and added HTTP-contract check. Search/list restoration and search-add/Undo UI tests passed on both iPhone 17 Pro and iPad Air 11-inch (M3), iOS 26.
- Existing app/widget build-number mismatch and `LoggingActionRouter` actor-isolation warning remain. No iOS archive, TestFlight upload or App Store release was performed.

### Credential activation follow-up

The owner saved both credentials locally and in Vercel Production. Redeployed and confirmed the local OAuth exchange succeeds without displaying tokens. Live food lookup was rejected with FatSecret code 21 (IP not allowed).

Production deployment `dpl_5WZGU31EqkaA7jTkXd1stPxekuif` is READY and aliased to `https://cavecals.vercel.app`. The production Urbane Cafe request confirms the same blocker: HTTP 503 `food_search_ip_denied`. This code now distinguishes IP denial from generic failure, with an analogous safe category for missing API scope; upstream account details are never returned. Typecheck and all 21 backend unit tests passed.

Next requirement: configure stable outbound IPs and allowlist them in FatSecret. A potential low-cost option is Fixie HTTP/HTTPS (500 proxied requests/month free, 2,500 for $5/month, or 25,000 for $19/month as checked September 21). It requires a new service/account connection and proxy configuration; nothing has been purchased, connected, or broadly allowlisted. Existing native tests remain valid; no iOS build was uploaded. Live restaurant results remain **unverified and blocked by the IP allowlist**, not by missing credentials.

References: [Fixie plans](https://usefixie.com/pricing), [HTTPS tunnel behavior](https://usefixie.com/documentation/http-and-https-requests).

## References

- [OAuth and server IP requirements](https://platform.fatsecret.com/docs/guides/authentication/oauth2)
- [Basic search](https://platform.fatsecret.com/docs/v1/foods.search)
- [Premier search v5](https://platform.fatsecret.com/docs/v5/foods.search)
- [Error codes](https://platform.fatsecret.com/docs/guides/error-codes)
- [Storage rules](https://platform.fatsecret.com/docs/guides/storable-data)
- [Attribution](https://platform.fatsecret.com/attribution)
- [Plans](https://platform.fatsecret.com/api-editions)

### Fixie transport support

The backend now accepts server-only `FIXIE_URL` and routes FatSecret OAuth/search through an Undici CONNECT proxy. Apple, OpenAI and other services retain their normal connections. TLS verification remains enabled; a broken proxy returns an error with no direct fallback. Set up the free Fixie integration for **only cavecals**, then allowlist both assigned outbound IPs in FatSecret. A redeploy alone cannot resolve code 21. As of this follow-up, setup stopped at Vercel browser sign-in because the owner chose to handle Vercel; no Fixie account or allowlist was changed by Codex.

References: [Vercel integration steps](https://usefixie.com/documentation/vercel), [Undici ProxyAgent](https://undici.nodejs.org/api/ProxyAgent).

Final live recheck after the owner's redeploy still returned HTTP 503 `food_search_ip_denied` for Urbane Cafe. The local Fixie transport change is tested and ready for deployment, but live proxy routing and restaurant results remain unverified until the service connection and FatSecret IP allowlist are configured.


### Fixie activation — live search verified

After the owner connected Fixie and added its IP addresses to FatSecret, confirmed that `FIXIE_URL` and both FatSecret credential names are present in Vercel Production (values were not printed). Deployed the prepared backend from the repository root. Deployment `dpl_31vm8WLrxiSxhoQYaY8WNGzuQQUH` is READY, at `https://cavecals-cs6b77e1j-phils-projects-e15f8e11.vercel.app`, aliased to `https://cavecals.vercel.app`.

Both live `Urbane Cafe` and `Urbane` searches returned HTTP 200, with eight Urbane Cafe menu items among the first 25 results. Verified examples: So-Cal Sandwich (800 kcal per sandwich), Salmon Bowl (745 kcal per bowl), Chocolate Chip Cookie (300 kcal per cookie). These are real provider responses through the production endpoint, not test fixtures. Basic-tier `cacheLifetime` remains zero. The prior IP-denial blocker is resolved.

Production smoke checks: privacy 200; private development test page 404; unsigned account/status 401. Vercel build succeeded. No additional code changes or iOS release were needed for this connection activation; the simulator build already using the FatSecret endpoint can retry its search. The App Store binary still requires its separately planned native update.


## Native release follow-up — September 21, 2026

Version **1.0.3 (2)** now includes these changes in App Store Connect, with Apple processing VALID and explicit Internal Testers membership (IN_BETA_TESTING). App Store version 1.0.3 is prepared with this build but has not been submitted for review or publicly released. See [current release readiness](Release/Readiness.md) for validation and outstanding physical-device checks.


## Premier Free attribution — September 21, 2026

Checked https://platform.fatsecret.com/attribution after the owner received Premier Free access. The approved text link is sufficient; a logo is optional. The exact website snippet is already live: `<a href="https://platform.fatsecret.com">Powered by fatsecret Platform API</a>`.

Added `Powered by fatsecret nutrition API (www.fatsecret.com)` to the existing App Store 1.0.3 description via App Store Connect, preserving the owner's other listing edits. The native approved link remains in You/About and now also appears on each food-content screen when FatSecret data is displayed: online/local search, Logged, Quick Add, Meals, food editing, meal editing/from-today selection, and meal portion/add. Saved records retain their `fatsecret:` identifiers, so the credit remains after logging or editing.

These additional native credits are prepared in 1.0.3 (3). The previously uploaded build 2 is already WAITING_FOR_REVIEW, as observed during this change; no review submission was withdrawn or replaced. The Premier API tier setting is separate from these attribution changes.
