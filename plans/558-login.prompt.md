## Plan: Cookie-Based Login (issue #558)

Replace Apache Basic Auth with a Perl-managed cookie/HMAC system. Apache validates nothing; `login.pm` issues and verifies signed tokens. The 401 flow causes the browser to send credentials once, after which it stays logged in via cookie. The module is designed to be reusable across other projects by sharing the same secret file and cookie name.

**Module loading convention**

`login.pm` loads its own dependencies with `use` so it is self-contained and reusable in other projects. `index.cgi` also lists the same modules in its own `use` block for documentation and so `perl -c` catches missing packages.

---

**Phase 1 — Create `login.pm` (commit, test standalone)**

1. **Create `code/login.pm`** with the following functions:

   Public (all take `$c`):
   - `authenticate($c)` — reads cookie or `HTTP_AUTHORIZATION` from `$c->{cgi}`; sets `$c->{username}` on success; sends 401 + exits on failure.
   - `prepare_cookie($c)` — builds a fresh token and stores a `CGI::Cookie` in `$c->{auth_cookie}` for `htmlhead()` to attach.
   - `logout($c)` — sends an expired cookie via `$c->{cgi}` and redirects to the app root, triggering a new login prompt.

   Internal helpers (not called externally):
   - `make_token($username, $secret)` — builds token string `username:expiry:hmac_hex` where HMAC-SHA256 is over `username:expiry`, expiry is `time() + 14*86400`.
   - `verify_token($token, $secret)` — splits token, recomputes HMAC, checks expiry; returns username or `undef`.

   Config block at top of file: `$HTPASSWD_FILE`, `$SECRET_FILE`, `$COOKIE_NAME`, `$COOKIE_MAX_AGE`.

2. **Perl module dependencies** — loaded in both `login.pm` and documented in `index.cgi`:
   - `Digest::SHA qw(hmac_sha256_hex)` — standard, for token signing.
   - `Authen::Htpasswd` — for `.htpasswd` validation. (`libauthen-htpasswd-perl` on Debian/Ubuntu.)
   - `CGI::Cookie` — ships with `CGI`, already used in the project.
   - `MIME::Base64 qw(decode_base64)` — standard, for parsing the Basic Auth header.

3. **Secret file `/etc/lsd/login.secret`** — one line of random bytes, created once manually (as root)
   (`openssl rand -hex 32 > /etc/lsd/login.secret`). Shared with other projects by pointing their
   `login.pm` config to the same file.

3b. **Create `tools/test-login.pl`** — standalone test script (not part of the CGI app):
   - Calls `make_token` and prints the token.
   - Calls `verify_token` on the result and prints the returned username.
   - Calls `verify_token` with a tampered token and confirms it returns `undef`.
   - Calls `verify_token` with an expired token (expiry set in the past) and confirms `undef`.
   - Prints PASS/FAIL for each case.

**Verification (phase 1)**:
- `perl -c code/login.pm` — no syntax errors.
- `perl tools/test-login.pl` — all cases print PASS.

---

**Phase 2 — Wire up `index.cgi` and add logout (commit, test in dev)**

4. **Modify `code/index.cgi`**:
   - Add `require "./code/login.pm";` near the other requires.
   - Line ~115: build a minimal `$c = { cgi => $q }` and call `login::authenticate($c)` to set
     `$c->{username}`; replace the existing `$q->remote_user()` block. Use `$c->{username}` when
     constructing the full `$c` hash below.
   - After the full `$c` is constructed: call `login::prepare_cookie($c)` to populate `$c->{auth_cookie}`.
   - In `htmlhead()` line ~326: add `-cookie => $c->{auth_cookie}` and `-Secure => 1` to `$q->header(...)`.
     No cookie needed on the POST redirect — browser retains the cookie through POST → redirect → GET.

5. Add a **logout** entry in the menu under More. It calls `login::logout($c)` and redirects to the
   root of the app (`/beertracker/` or `/beertracker-dev/`), triggering a new login prompt.

6. **Update `code/aboutpage.pm`**: correct the "uses no cookies" claim to mention the session cookie.

**Verification (phase 2)**: In dev (Apache auth already removed from dev block): clear cookies → browser prompts once → cookie issued → subsequent GETs skip prompt → logout works → tampered cookie triggers 401.

---

**Phase 3 — Phased Apache config changes (three sub-steps, no downtime)**

7. **Sub-step A** — add `CGIPassAuth On` to the Apache config while *keeping* Basic Auth. Commit, pull
   to production, reload Apache. Production still works; Apache now passes the `Authorization` header
   through to CGI so the cookie layer can see credentials. No Perl changes.

8. **Sub-step B** — deploy the `login.pm` + `index.cgi` changes (phases 1 & 2) to production. Both
   auth layers are now active simultaneously: Apache requires credentials, `login.pm` validates them
   and issues a cookie. Cookie path is live and testable in production.

9. **Sub-step C** — remove `AuthUserFile`, `AuthName`, `AuthType Basic`, `Require valid-user` from
   `etc/apache-config.example.txt`. Commit, pull to production, reload Apache. Cookie is now the sole
   auth layer.

**Verification (phase 3)**: After sub-step C: clear cookies on a device that has not logged in → browser prompts for credentials → cookie issued → subsequent visits skip prompt. Confirm sharing `/etc/lsd/login.secret` with another app accepts the same cookie.

**Decisions**

- Passwords validated against existing `.htpasswd` — no user migration needed.
- Stateless HMAC token — no DB/session table needed.
- Cookie is `path=/`, `HttpOnly`, `Secure`, `SameSite=Strict`.
- Cookie only sent on GET responses via `htmlhead()`; browser retains it through POST redirects.
- `CGIPassAuth On` is essential: without it Apache silently drops the `Authorization` header.
