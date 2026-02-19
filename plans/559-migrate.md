# 559-migrate.md — DB migration system (Perl module)

Status: proposal / planning only (no code changes in this PR)

## Goal
Implement a small, in-process migration system in `code/dbmigrate.pm` that:
- detects when the DB is older than the running code and shows a confirmation form (GET) which POSTs to `o=migrate`;
- runs forward-only migrations implemented as Perl subs registered in `@MIGRATIONS`;
- records the current DB version in a minimal `globals` table (`db_version` integer);
- writes concise progress to STDERR and creates a timestamped local DB backup before any write;
- supports the existing dev flow (copy prod DB into dev and re-run migrations repeatedly).

**Simplifications:** forward-only migrations, no CLI, no external scheduler. `code_db_version` is a hard-coded constant in `code/dbmigrate.pm` (update it when you add migrations).

---

## Key rules (short)
- Migrations are one-way Perl subs registered in `@MIGRATIONS` as `[id, description, \&sub]`.
- `code_db_version` is hard-coded inside `code/dbmigrate.pm`.
- No superuser check required (single-developer environment).
- Backups are a timestamped file copy (safe because DB is opened read-only at that point). Keep last 3.
- Run migrations inside the normal POST transaction; on error the transaction rolls back and `db_version` stays unchanged.

---

## Design (concise)
- Module: `code/dbmigrate.pm`.
- Migration list: explicit `@MIGRATIONS` array; the runner executes entries with id > `globals.db_version` in list order.
- Storage: single `globals` table item `db_version` (integer).
- Logging: STDERR only; set `$c->{migrating}=1` during runs for verbose logging.

---

## Runtime flow
- startup_check($c) — called from `index.cgi` after `db::open_db($c,'ro')` and before `htmlhead()`:
  - Read `globals.db_version` (missing `globals` → treat as 0).
  - If DB version > code version → fatal `util::error()`.
  - If DB version < code version → take timestamped backup (file copy), set `$c->{op}='migrate'`, return.
- migrate_form($c) — shows current vs code version, pending migrations, and a single POST button.
- run_migrations($c) — POST handler inside the normal `BEGIN TRANSACTION` / `COMMIT` block:
  - Set `$c->{migrating}=1`.
  - Iterate `@MIGRATIONS`, skip ids <= stored `db_version`, run each migration, update `globals.db_version` after each success.
  - On error the shared transaction rolls back and `db_version` is unchanged. Log to STDERR.

Note: no additional concurrency controls or re-check are required for this single-developer setup.

---

## First migration (required)
`mig_001_create_globals_table` must create `globals` and set `db_version = 0`. `startup_check` treats a missing `globals` table as version 0 so the runner can create it.

Example SQL:

  CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT);
  INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0');

---

## Writing migrations (rules)
- Add functions named `mig_NNN_description` and register each in `@MIGRATIONS` in numeric order.
- Use `db::execute($c, $sql, @params)` for DDL/DML inside migrations (it logs + executes).
- Keep migrations small and quick; DB is small so long-running backfills are uncommon.

Example registration:

  our @MIGRATIONS = (
    [1, 'create globals table', \&mig_001_create_globals_table],
    [2, 'add taps.last_seen',  \&mig_002_add_taps_last_seen],
  );

---

## Backups
- Performed in `startup_check` (before any write transaction).
- Implemented as timestamped file copies: `beerdata/beertracker.db.bak.YYYYMMDDTHHMMSS`.
- Keep the last 3 backups; log creation/rotation to STDERR.
- Pure file copy is acceptable here because DB is opened read-only at backup time.

---

## Safety guarantees
- Forward-only migrations; atomicity via the shared POST transaction; on error the DB rolls back and `db_version` is unchanged.
- `globals.db_version` is the single source of truth for migration state.
- No special access control required (single-developer environment).

---

## Implementation checklist (minimal)
1. Add `db::execute($c,$sql,@params)` to `code/db.pm`.
2. Add `code/dbmigrate.pm` (startup_check, migrate_form, run_migrations, backups, `@MIGRATIONS`, hard-coded `code_db_version`).
3. Add `mig_001_create_globals_table` and any migrations required to match `code/db.schema`.
4. Wire `index.cgi`: call `dbmigrate::startup_check($c)` after `db::open_db($c,'ro')` and add GET/POST `o=migrate` branches. No access-control required.
5. Manually verify, run `tools/dbdump.sh` and commit `code/db.schema` updates.

---

## Acceptance criteria (brief)
- startup_check is a no-op when DB is current.
- startup_check errors if DB version > hard-coded `code_db_version`.
- startup_check takes a backup and triggers `migrate_form` when DB is behind.
- migrate_form shows pending migrations.
- run_migrations runs pending migrations in order, logs to STDERR, updates `globals.db_version`, and rolls back on error.

---

## Tests & manual verification
- Copy production DB into dev and confirm the migration form appears.
- Run migrations and verify backups, STDERR logs, and that `globals.db_version` updated.
- Cause a migration to fail and confirm the transaction rolls back and `db_version` is unchanged.

---

## Next step
If this looks correct I will scaffold `code/dbmigrate.pm` (skeleton + example migration) when you give the go-ahead. No code changes will be made until you explicitly ask.
