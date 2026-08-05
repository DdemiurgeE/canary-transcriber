# Project Agent Context

This file is automatically injected into every Hermes conversation in this project.
Update the sections below to match your project.

---

## Project Overview

> **TODO**: Replace with your project description.
> Example: "REST API for a task management SaaS. Python 3.12, FastAPI, PostgreSQL 16, Redis."

**Stack**: <language> <framework> <database> <other key deps>
**Repo root**: <absolute path>
**Test command**: <e.g., `pytest -x -q` or `npm test`>
**Lint command**: <e.g., `ruff check .` or `eslint src/`>
**Run locally**: <e.g., `uvicorn app.main:app --reload`>

---

## Service Vision

> **TODO**: Describe the long-term architectural direction.
> The Service Vision controller reads this to evaluate alignment.

- **Core principle**: <e.g., "API-first, async by default, zero downtime deploys">
- **Approved tech additions**: <e.g., "Celery for async tasks, S3 for file storage">
- **Explicitly avoided**: <e.g., "No Django ORM, no monkeypatching, no global state">
- **Roadmap themes**: <e.g., "Q3: multi-tenancy, Q4: real-time notifications">

---

## Directory Layout

```
<project_root>/
  src/           # application source
  tests/         # test suite
  migrations/    # database migrations
  docs/          # technical documentation
  pipeline/      # AI pipeline artifacts (auto-generated, gitignored)
```

---

## Pipeline Artifacts

All pipeline artifacts live under `pipeline/<stage_id>/`:

| File pattern | Written by | Purpose |
|---|---|---|
| `STAGE_<id>.md` | Planner | Stage specification |
| `STAGE_<id>_REVIEW.md` | Reviewer | Review verdict |
| `STEPS_MANIFEST.md` | Decomposer | Ordered step list |
| `STEP_ID_<n>_<name>.md` | Decomposer | Step specification |
| `STEP_<n>_EXPLORE.md` | Explorer | Codebase map for step |
| `STEP_<n>_OUTPUT.md` | Implementer | Implementation result |
| `STEP_<n>_CHECK.md` | Critic | Validation verdict |
| `CTRL_*.md` | Controllers | Specialist reviews |
| `STAGE_<id>_ISSUES.md` | Orchestrator | Open issues log |
| `last_verified_commit` | Orchestrator | Last clean git SHA |

Add `pipeline/` to `.gitignore` or commit it — your choice.

---

## Coding Conventions

> **TODO**: Add project-specific conventions.

- <e.g., "All public functions must have docstrings">
- <e.g., "Use `logger = logging.getLogger(__name__)` in every module">
- <e.g., "Migrations must be reversible — always provide `downgrade()`">

---

## Contacts / Escalation

> **TODO**: Who to ping for decisions.

- Architecture decisions: <name/handle>
- Security questions: <name/handle>
- DB schema changes: <name/handle>
