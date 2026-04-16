---
description: "Create a structured implementation plan document for a BeerTracker feature. Use when: planning a new feature, designing a change across multiple modules, or before starting any multi-step implementation."
argument-hint: "<issue number>"
agent: "agent"
---

You are creating a plan document for the BeerTracker codebase. The argument is an issue number, e.g. `670`.

## Step 1 — Understand the feature

Fetch the GitHub issue using `github-pull-request_issue_fetch` with repo `owner: heikkilevanto`, `name: beertracker` and the given issue number. If no argument is given, ask for the issue number. Read the issue title, body, **and all comments** thoroughly — this is the primary source of truth for what to build.

Use the issue title as the feature description. Use the issue body and comments to understand requirements, constraints, and any prior design decisions.

## Step 2 — Explore the codebase

Explore the codebase as needed based on the issue. 
Only read [doc/db.schema](../../doc/db.schema) if the feature involves DB changes or you need to understand the schema.
Check `plans/` for any related prior plans, but not `plans/done`.

## Step 3 — Draft the plan

Write a plan document with these sections (omit sections that don't apply):

```
# Plan: <Feature name> (issue #<N>)

## Decisions
Bullets for any design choices made upfront (DB column names, UI placement,
behaviour on edge cases, what is explicitly out of scope).

## Database changes
List new tables, columns, views, indexes. Each change must map to a
`migrate.pm` migration. Note if an ALTER TABLE requires a manual step.
Remind that `tools/dbdump.sh` must be run after schema changes.

## Phases
Break work into small, independently testable steps.
Each step: a single file or concern. Reference actual function names
and module paths where known.

## Open questions
Anything that needs a decision before or during implementation.
```

Keep the plan concrete and file-specific. Reference real module names (`code/brews.pm`), real function names, and real SQL column names where known. Do not invent names — if unsure, say so.

## Step 4 — Save the plan

Derive a short slug from the feature description (lowercase, hyphens, max 4 words).
Save the plan to `plans/<issue>-<slug>.md`. Open it in the editor.

Confirm the saved path to the user and note any open questions that need answers before implementation begins. Do NOT start implementing — the plan is the only output.
