# 559-migrate.md — DB migration system (Perl module)

Status: proposal / planning only (no code changes in this PR)

## Goal
Keep migrations simple and in‑process: implement a new Perl module `code/dbmigrate.pm` that
- detects when the DB is behind the code; `startup_check` renders a confirmation form (before any routing) that the user submits as POST to `o=migrate`;
- runs ordered migrations implemented as Perl functions listed in a `@MIGRATIONS` array inside the module (no down/rollback migrations);
- records only the current DB version in a small `globals` table;
- logs progress to STDERR; no browser streaming;
- automatically creates a local DB backup (keeps a few generations) inside `startup_check` before showing the form — before any write transaction opens;
- supports the dev flow where you copy production DB into dev/test and re-run migrations repeatedly.

**Constraints / simplifications:** no downgrade paths, no manual/long-running flags, no CLI helper — everything lives in `code/dbmigrate.pm` and is invoked from the web UI (`index.cgi`).

---

## Design overview (simple, opinionated)
- Module: `code/dbmigrate.pm` — single place for migration logic and the migration functions.
- Migration representation: named Perl subs inside the module, e.g. `sub migrate_001_add_last_seen { my ($c) = @_; ... }`.
  - Discovery: via an explicit `@MIGRATIONS` list (ordered array of `[id, description, \&function_ref]` tuples). The runner iterates the list and executes entries with id > current_db_version. No symbol-table introspection.
  - No `down`/rollback functions — migrations are one-way.
- DB version storage: a tiny `globals` table holds `db_version` (integer). Example schema:
  CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT);
  INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','3');
- Transaction handling: `o=migrate` uses the **same** shared `BEGIN TRANSACTION` / `COMMIT` / rollback-on-error flow as every other POST handler in index.cgi. No special-casing needed — the backup is already taken before the form is shown, so the DB is safe before the transaction opens. SQLite DDL (CREATE TABLE, ALTER TABLE) is transactional and will roll back cleanly on error.
- Logging: write concise progress messages to STDERR. When `$c->{migrating}` is set (see below), emit extra detail (similar to `$c->{devversion}`).
- `$c->{migrating}` flag: set to 1 by `run_migrations` at the start of the run; checked by migration functions and db helpers for verbose logging.

---

## Runtime behaviour

### `dbmigrate::startup_check($c)` (called on the GET path, before routing)
- Called from index.cgi after `db::open_db($c, 'ro')` and before `htmlhead()` (i.e., before any HTTP headers are sent).
- Reads `globals.db_version` (or treats it as 0 if the `globals` table does not yet exist).
- If `db_version` == `code_db_version`: returns immediately — nothing to do.
- If `db_version` > `code_db_version`: **fatal error** — the database is newer than the running code. Call `util::error("DB version $db_version is newer than code version $code_db_version — deploy the latest code first")`. Do not attempt to run.
- If `db_version` < `code_db_version`:
  1. Takes a timestamped DB backup and rotates old backups (pure file copy — no write transaction involved).
  2. Sets `$c->{op} = 'migrate'` and returns. Normal GET routing then dispatches to `dbmigrate::migrate_form($c)` via the `elsif ($c->{op} =~ /migrate/i)` branch added to index.cgi.

### GET handler: `dbmigrate::migrate_form($c)`
- Called from index.cgi's normal GET routing chain when `$c->{op} eq 'migrate'`.
- Renders a page (inside the normal HTML head/footer) showing:
  - current DB version vs. code version,
  - list of pending migration names from `@MIGRATIONS`,
  - a single "Run migrations" button that POSTs to `?o=migrate`.

### `o=migrate` POST handler (`dbmigrate::run_migrations($c)`)
- Dispatched from index.cgi's POST block like any other handler — **no special-casing**; it runs inside the normal `BEGIN TRANSACTION` / `COMMIT` / rollback-on-error block.
- Sets `$c->{migrating} = 1` for verbose logging throughout the run.
- Iterates `@MIGRATIONS` skipping ids <= current `db_version`, runs each function in order, updates `globals.db_version` after each one.
- On error the shared transaction rolls back; `db_version` remains unchanged.
- Logs each step to STDERR (verbosely when `$c->{migrating}` is set). On success the normal redirect at the end of the POST block sends the user back to `?o=migrate` (or the main page).

### Backup
- Timestamped copy: `beerdata/beertracker.db.bak.YYYYMMDDTHHMMSS`.
- Keep the last 3 backups (constant in the module); older ones are deleted.
- Backup happens in `startup_check`, before the form is shown and before any write transaction.

### Idempotence
- Runner skips migrations with id <= stored `db_version`, so the same DB can be migrated repeatedly (e.g. after copying prod DB to dev).

---

## First migration (required)
The very first migration must create the `globals` table and set `db_version` to 0 so the migration runner can discover and update the DB version correctly. `startup_check` must be resilient: if the `globals` table does not exist, treat the current DB version as 0 and run `mig_001_create_globals_table` first.

Example SQL executed by `migrate_001_create_globals_table`:

  CREATE TABLE IF NOT EXISTS globals (
    k TEXT PRIMARY KEY,
    v TEXT
  );
  INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0');

Example function (inside `code/dbmigrate.pm`):

  sub mig_001_create_globals_table {
    my ($c) = @_;
    db::execute($c, "CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT)");
    db::execute($c, "INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0')");
    return 1;
  }

---

## How to write a migration (example)

Add an entry to `@MIGRATIONS` and write the corresponding sub:

  our @MIGRATIONS = (
    [ 1, 'create globals table',  \&mig_001_create_globals_table ],
    [ 2, 'add last_seen to taps', \&mig_002_add_taps_last_seen   ],
    # add new entries here
  );

  sub mig_002_add_taps_last_seen {
    my ($c) = @_;
    db::execute($c, "ALTER TABLE taps ADD COLUMN last_seen INTEGER DEFAULT 0");
    # small data fixup if needed
    db::execute($c, "UPDATE taps SET last_seen = strftime('%s','now') WHERE last_seen IS NULL");
    return 1;
  }

- Naming: `mig_NNN_short_description` (NNN is zero-padded numeric id). Keep functions small and quick.
- Register every function in `@MIGRATIONS` in numeric order — the runner iterates the list, it does not sort or discover.
- Use `db::execute($c, $sql, @params)` for all DDL and DML inside migrations — it logs the statement to STDERR (verbosely when `$c->{migrating}` is set) and calls `$c->{dbh}->do`. Use `db::query` / `db::queryrecord` for SELECT. Do not call `$c->{dbh}->do` directly in migration functions.

---

## Backups
- Before any migration the module copies the DB file to `beerdata/beertracker.db.bak.YYYYMMDDTHHMMSS`.
- Keep the last 3 backups by default (configurable via a `$c` setting or constant).
- Log backup creation and rotation to STDERR.

---

## Safety & guarantees (practical)
- No downgrades: migrations are forward-only.
- Atomicity: the migration module manages its own transaction. On error the transaction rolls back and `db_version` remains at the prior value. SQLite DDL is transactional, so partial schema changes also roll back.
- Logging: every step is logged to STDERR. Check the server error log if a migration fails.
- Simplicity: only one persistent datum (globals.db_version) — easier to inspect and maintain.

---

## Developer workflow (dev/test)
- Copy production DB into dev (e.g. `superuser::copyproddata()` or file copy).
- Open any page; `startup_check` detects the older DB, takes a backup, and renders the migration form.
- Submit the form; `o=migrate` runs pending migrations and redirects to the main page.
- Because we store only `db_version`, repeated copies of production DB will trigger the form and migrate automatically.
- After a new migration has been verified, run `tools/dbdump.sh` manually to update `code/db.schema` and commit.
- Once the migration system is stable, deprecate `tools/dbchange.sh` and the `tools/warn-schema.sh` git post-merge hook — schema changes will be managed exclusively through migrations.

---

## Files to add / modify (implementation step later)
- Add: `code/dbmigrate.pm` (module with `@MIGRATIONS` list, migration functions, `startup_check`, `migrate_form`, `run_migrations`, and backup/rotate helpers).
- Modify: `code/db.pm` — add `db::execute($c, $sql, @params)`: logs the statement (extra detail when `$c->{migrating}`) and calls `$c->{dbh}->do($sql, undef, @params)`.
- Modify: `code/index.cgi`:
  - GET path: call `dbmigrate::startup_check($c)` after `db::open_db($c,'ro')` and before `htmlhead()`; add `elsif ($c->{op} =~ /migrate/i) { dbmigrate::migrate_form($c); }` to the GET routing chain.
  - POST path: add `elsif ($c->{op} =~ /migrate/i) { dbmigrate::run_migrations($c); }` inside the existing `BEGIN TRANSACTION` block — no special-casing required.
- Update: `plans/559-migrate.md` (this file).

(No CLI; no separate migration tables.)

---

## Acceptance criteria
- `startup_check` returns immediately when the DB is current.
- `startup_check` calls `util::error` (fatal) when `db_version` > `code_db_version`.
- `startup_check` takes a backup, sets `$c->{op} = 'migrate'`, and returns when migrations are pending; the GET routing chain then renders the form.
- `migrate_form` shows pending migration names and a POST button.
- `run_migrations` runs pending `@MIGRATIONS` entries inside the normal shared transaction (no special-casing in index.cgi).
- Every migration step is logged to STDERR; `$c->{migrating}` enables verbose logging.
- After a successful run `globals.db_version` equals the highest id in `@MIGRATIONS`.
- On error the transaction rolls back and `db_version` is unchanged.
- Backups are created and rotated by `startup_check` before the form is shown.

---

## Design decisions (resolved)

| # | Issue | Decision |
|---|-------|----------|
| 1 | Cannot HTTP-redirect to a POST | `startup_check` renders its own HTML page with a form that POSTs to `o=migrate`. JS auto-submit can be added later. |
| 2 | No GET routing for `o=migrate` | `startup_check` sets `$c->{op}='migrate'` and returns; normal GET routing dispatches to `dbmigrate::migrate_form($c)`. A `elsif (/migrate/i)` branch is added to index.cgi. |
| 3 | Streaming conflicts with redirect-after-POST | No streaming. All progress logged to STDERR only. |
| 4 | Backup timing vs. shared transaction | Backup done in `startup_check` (file copy, before the form is shown). POST uses the normal shared transaction — no special-casing. |
| 5 | SQLite transactional DDL | Noted: SQLite DDL rolls back cleanly inside a transaction. Backups provide additional safety. |
| 6 | `@MIGRATIONS` list vs. symbol-table discovery | Use an explicit `@MIGRATIONS` array of `[id, description, \&function_ref]` tuples. Clearer and consistent with codebase style. |
| 7 | Placement of `startup_check` in index.cgi | Called on the GET path after `db::open_db($c, 'ro')` and before `htmlhead()`. The `copyproddata` path exits before `open_db`, so `startup_check` is never reached there — acceptable. |
| 9 | DB version newer than code | Fatal `util::error` in `startup_check` — do not attempt to run against a newer DB. |
| 10 | Verbose migration logging | `$c->{migrating} = 1` set at run start; checked by `db::execute` and migration functions, analogous to `$c->{devversion}`. |
| 11 | `$c->{dbh}->do` in migration functions | Add `db::execute($c, $sql, @params)` to db.pm (logs + executes). All DDL/DML in migration functions uses this; no bare `$c->{dbh}->do` calls. |
| 8 | `code/db.schema` update after migrate_001 | Run `tools/dbdump.sh` manually after verifying the migration, then commit. Future: may drop dbdump/dbchange entirely. |

---

## Implementation plan (phased, minimal)
1. Add `db::execute($c, $sql, @params)` to `code/db.pm`.
2. Add module skeleton `code/dbmigrate.pm` with: `startup_check`, `migrate_form`, `run_migrations`, backup/rotate helpers, and `@MIGRATIONS` list.
3. Add `mig_001_create_globals_table` plus any migrations needed to align the DB to the current `code/db.schema`.
4. Wire `index.cgi`: call `dbmigrate::startup_check($c)` on the GET path (before routing); add `elsif (/migrate/i)` branches to both GET and POST routing chains.
5. Manual verification; run `tools/dbdump.sh` to update `code/db.schema`; commit.
6. Update `doc/design.md` to document the new migration workflow. Deprecate `tools/dbchange.sh` (no longer needed — migrations handle schema updates in-process). Remove or disable the git post-merge hook in `tools/warn-schema.sh` that warns about schema changes (the migration system makes that warning redundant).

---

## Tests & manual verification
- Copy production DB into dev and confirm `index.cgi` shows the migration form at `o=migrate`.
- Run the web migration and verify backups, STDERR logs, and that `globals.db_version` is updated.
- Simulate a migration failure (raise an error inside a migration function) to verify the transaction rolls back and `db_version` is unchanged.

---

## Next step
If this simplified plan looks good I will scaffold `code/dbmigrate.pm` (module skeleton + UI) and add one example migration that brings the DB to the code's expected version. No code changes will be made until you explicitly give the go-ahead — this plan remains a proposal until you confirm. Proceed with scaffolding or tell me if you want any other small changes to the plan.
