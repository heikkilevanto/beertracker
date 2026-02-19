# 559-migrate.md — DB migration system (Perl module)

Status: proposal / planning only (no code changes in this PR)

## Goal
Keep migrations simple and in‑process: implement a new Perl module `code/dbmigrate.pm` that
- detects when the DB is behind the code and (at startup) causes `index.cgi` to POST `o=migrate`;
- runs ordered migrations implemented as Perl functions inside the module (no down/rollback migrations);
- records only the current DB version in a small `globals` table;
- shows a streaming running commentary on `o=migrate` and logs progress to STDERR;
- automatically creates a local DB backup (keeps a few generations) before applying changes;
- supports the dev flow where you copy production DB into dev/test and re-run migrations repeatedly.

**Constraints / simplifications:** no downgrade paths, no manual/long-running flags, no CLI helper — everything lives in `code/dbmigrate.pm` and is invoked from the web UI (`index.cgi`).

---

## Design overview (simple, opinionated)
- Module: `code/dbmigrate.pm` — single place for migration logic and the migration functions.
- Migration representation: named Perl subs inside the module, e.g. `sub migrate_001_add_last_seen { my ($c) = @_; ... }`.
  - Discovery: the runner discovers `migrate_NNN_...` subs by name (or via a small @MIGRATIONS list); it sorts by numeric prefix and executes functions with NNN > current_db_version.
  - No `down`/rollback functions — migrations are one-way.
- DB version storage: a tiny `globals` table holds `db_version` (integer). Example schema:
  CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT);
  INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','3');
- Transaction handling: `index.cgi` already wraps POST requests in a transaction — the migration runner will rely on that when invoked via the web UI. (We will ensure the runner is safe to call outside index.cgi later if needed.)
- Logging: write concise progress messages to STDERR and stream the same messages to the browser during the POST that runs migrations.

---

## Runtime behaviour (index.cgi + `o=migrate`)
- On startup `index.cgi` calls `dbmigrate::startup_check($c)`.
  - If stored `db_version` < `code_db_version` (highest migration NNN in the module) `startup_check` will redirect to `?o=migrate` (POST flow).
- `o=migrate` page:
  - shows current DB version vs expected code version,
  - lists pending migration function names/descriptions,
  - is POST-only and does not prompt; pending migrations are executed immediately,
  - during POST the module prints step-by-step messages to the HTTP response (printed + flushed) and to STDERR; when finished it updates `globals.db_version` and shows a link back to the main page.
- Backup: before applying any migration the module will create a DB backup file (timestamped) and rotate/keep the last N generations (configurable, default N=3). Backups are stored under `beerdata/` alongside the DB.
- Idempotence: runner skips migrations with id <= stored `db_version` so the same DB can be migrated repeatedly.

---

## First migration (required)
The very first migration must create the `globals` table and set `db_version` to 0 so the migration runner can discover and update the DB version correctly. `startup_check` must be resilient: if the `globals` table does not exist, treat the current DB version as 0 and run `migrate_001_create_globals_table` first.

Example SQL executed by `migrate_001_create_globals_table`:

  CREATE TABLE IF NOT EXISTS globals (
    k TEXT PRIMARY KEY,
    v TEXT
  );
  INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0');

Example function (inside `code/dbmigrate.pm`):

  sub migrate_001_create_globals_table {
    my ($c) = @_;
    $c->{dbh}->do("CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT)");
    $c->{dbh}->do("INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0')");
    db::logquery($c, "Created globals table and set db_version=0");
    return 1;
  }

---

## How to write a migration (example)
- Function-style migration (recommended):

  sub migrate_003_add_taps_last_seen {
    my ($c) = @_;
    $c->{dbh}->do("ALTER TABLE taps ADD COLUMN last_seen INTEGER DEFAULT 0");
    # small data fixup if needed
    $c->{dbh}->do("UPDATE taps SET last_seen = strftime('%s','now') WHERE last_seen IS NULL");
    return 1;
  }

- Naming: `migrate_NNN_short_description` (NNN is zero-padded numeric id). Keep functions small and quick.

- Use db.pm helpers where possible: prefer `db::logquery($c, $sql, @params)` for consistent STDERR logging, `db::query` / `db::queryrecord` for selects, and `$c->{dbh}->do` for DDL or simple statements. Using these helpers keeps migration logging and error handling consistent with the rest of the codebase.

---

## Backups
- Before any migration the module copies the DB file to `beerdata/beertracker.db.bak.YYYYMMDDTHHMMSS`.
- Keep the last 3 backups by default (configurable via a `$c` setting or constant).
- Log backup creation and rotation to STDERR.

---

## Safety & guarantees (practical)
- No downgrades: migrations are forward-only.
- Atomicity: `index.cgi`'s POST transaction covers the migration run — on error the transaction is rolled back and the DB remains at the prior version.
- Logging: every step is logged to STDERR and streamed to the browser so failures are visible.
- Simplicity: only one persistent datum (globals.db_version) — easier to inspect and maintain.

---

## Developer workflow (dev/test)
- Copy production DB into dev (e.g. `superuser::copyproddata()` or file copy).
- Start the app; `index.cgi` will detect the older DB and POST to `o=migrate`.
- `o=migrate` runs pending migrations immediately (no prompts) and the DB is upgraded.
- Because we store only `db_version`, repeated copies of production DB will be migrated automatically.

---

## Files to add / modify (implementation step later)
- Add: `code/dbmigrate.pm` (module with migration functions, backup + runner, and `migrate_ui($c)`).
- Modify: `code/index.cgi` — call `dbmigrate::startup_check($c)` on startup and route `?o=migrate` to `dbmigrate::migrate_ui($c)`.
- Update: `plans/559-migrate.md` (this file).

(No CLI; no separate migration tables.)

---

## Acceptance criteria
- `dbmigrate::status($c)` returns `db_version` (from `globals`) and the highest migration id in code.
- `index.cgi` startup check redirects to `o=migrate` when the DB is behind.
- `o=migrate` endpoint is POST-only, runs pending migrations, and streams step-by-step output while running them.
- Backups are created and rotated before migration.
- After successful run `globals.db_version` equals `code_db_version`.

---

## Implementation plan (phased, minimal)
1. Add module skeleton `code/dbmigrate.pm` with: startup_check, status, migrate_ui, run_pending, backup/rotate helpers.
2. Add 2–3 example migration functions to align DB to current `code/db.schema` if needed.
3. Wire `index.cgi` to call `startup_check` and route `o=migrate` to the module UI.
4. Manual verification and small fixes (no CLI, no extra DB tables).

---

## Tests & manual verification
- Copy production DB into dev and confirm `index.cgi` redirects to `o=migrate`.
- Run the web migration and verify backups, STDERR logs, and that `globals.db_version` is updated.
- Simulate a migration failure (raise an error inside a migration function) to verify the transaction rolls back and `db_version` is unchanged.

---

## Next step
If this simplified plan looks good I will scaffold `code/dbmigrate.pm` (module skeleton + UI) and add one example migration that brings the DB to the code's expected version. No code changes will be made until you explicitly give the go-ahead — this plan remains a proposal until you confirm. Proceed with scaffolding or tell me if you want any other small changes to the plan.
