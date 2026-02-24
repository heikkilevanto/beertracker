## Plan: Cookie-Based Login (issue #558)

Replace Apache Basic Auth with a Perl-managed cookie/HMAC system. Apache validates nothing; `login.pm` issues and verifies signed tokens. The 401 flow causes the browser to send credentials once, after which it stays logged in via cookie. The module is designed to be reusable across other projects by sharing the same secret file and cookie name.

**Steps**

1. **Create `code/login.pm`** with the following functions:

   Public (all take `$c`):
   - `authenticate($c)` — reads cookie or `HTTP_AUTHORIZATION` from `$c->{cgi}`; sets `$c->{username}` on success; sends 401 + exits on failure.
   - `prepare_cookie($c)` — builds a fresh token and stores a `CGI::Cookie` in `$c->{auth_cookie}` for `htmlhead()` to attach.
   - `logout($c)` — sends an expired cookie via `$c->{cgi}` and redirects to the app root, triggering a new login prompt.

   Internal helpers (not called externally):
   - `make_token($username, $secret)` — builds token string `username:expiry:hmac_hex` where HMAC-SHA256 is over `username:expiry`, expiry is `time() + 14*86400`.
   - `verify_token($token, $secret)` — splits token, recomputes HMAC, checks expiry; returns username or `undef`.

   Config block at top of file: `$HTPASSWD_FILE`, `$SECRET_FILE`, `$COOKIE_NAME`, `$COOKIE_MAX_AGE`.

2. **Perl module dependencies** in `login.pm`:
   - `Digest::SHA qw(hmac_sha256_hex)` — standard, for token signing.
   - `Authen::Htpasswd` — for `.htpasswd` validation. (`libauthen-htpasswd-perl` on Debian/Ubuntu.)
   - `CGI::Cookie` — ships with `CGI`, already used in the project.
   - `MIME::Base64 qw(decode_base64)` — standard, for parsing the Basic Auth header.

3. **Secret file `/etc/lsd/login.secret`** — one line of random bytes, created once manually (as root)
   (`openssl rand -hex 32 > /etc/lsd/login.secret`). Shared with other projects by pointing their
   `login.pm` config to the same file.

4. **Modify `code/index.cgi`** — three changes:
   - Line ~115: build a minimal `$c = { cgi => $q }` and call `login::authenticate($c)` to set `$c->{username}`; replace the existing `$q->remote_user()` block. Then use `$c->{username}` when constructing the full `$c` hash below.
   - After the full `$c` is constructed: call `login::prepare_cookie($c)` to populate `$c->{auth_cookie}`.
   - In `htmlhead()` line ~326: add `-cookie => $c->{auth_cookie}` and `-Secure => 1` to `$q->header(...)`.
     No cookie needed on the POST redirect — browser retains the cookie through POST → redirect → GET.
   - Add `require "./code/login.pm";` near the other requires.

5. **Update `etc/apache-config.example.txt`**: remove `AuthUserFile`, `AuthName`, `AuthType Basic`,
   `Require valid-user` from the `<DirectoryMatch>` block. Add `CGIPassAuth On` — required so Apache
   passes the `Authorization` header through to the CGI script.

6. **Update `code/aboutpage.pm`**: correct the "uses no cookies" claim to mention the session cookie.

7. Add a **logout** point in the menu under More. Clicking it calls `login::logout($c)` and redirects to the root of the app (the first segment of the url, here `/beertracker/` or `beertracker-dev/`). This will trigger a new login prompt.

**Verification**

- Clear browser cookies, visit site → browser prompts for credentials → accepts once → cookie issued → subsequent requests skip prompt.
- Verify cookie renews on each GET response.
- Try to log out
- Test wrong password → 401 again.
- Test expired/tampered cookie → 401 challenge.
- Confirm other apps sharing `/etc/lsd/login.secret` accept the same cookie.

**Decisions**

- Passwords validated against existing `.htpasswd` — no user migration needed.
- Stateless HMAC token — no DB/session table needed.
- Cookie is `path=/`, `HttpOnly`, `Secure`, `SameSite=Strict`.
- Cookie only sent on GET responses via `htmlhead()`; browser retains it through POST redirects.
- `CGIPassAuth On` is essential: without it Apache silently drops the `Authorization` header.
