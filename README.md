# taskfile-skill

A [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) that enforces consistent conventions when creating or editing Taskfile.yml and `.taskfiles/` module files ([taskfile.dev](https://taskfile.dev)).

---

> LLM/AI WARNING
>
> This project was largely written by [Claude](https://claude.ai/).
> It has been reviewed and tested, but use in production at your own discretion.
>
> LLM/AI WARNING

---

## What it does

When loaded, the skill ensures every Taskfile.yml Claude generates follows a strict set of conventions:

- `version: '3'` on every file
- `default` task listed first, running `task --list`
- Includes namespaced under `.taskfiles/<name>.yml`
- `desc:` field on every public task
- Destructive tasks use `prompt:` for confirmation and desc includes "DESTRUCTIVE"
- `vars:` with template defaults for all variables
- Standard top-level task names (`dev`, `test`, `build`, `lint`, `fmt`, `check`, `clean`)
- Standard task names enforced (`test`, not `run-tests`; `lint`, not `do-lint`)
- `check` meta-task required when 2+ quality gates exist
- Internal `task:` calls instead of `cmd: task` subprocess calls
- `ARGS` variable pattern with `CLI_ARGS` fallback for argument passthrough

The skill includes a lint script (`lint.sh`) that validates all deterministic rules. The LLM runs it after generating files and fixes any failures before finishing.

Without the skill, Claude generates valid but inconsistent Taskfiles. With it, output is uniform across single-file projects, multi-module setups, edits to existing files, and casual prompts.

## Benchmark

Evaluated across 10 scenarios (single-file, multi-module, destructive tasks, editing existing files, adding includes, casual prompts, multi-domain extraction, minimal-prompt standard tasks):

|                | Pass Rate |
|----------------|-----------|
| **With skill** | **100%**  |
| Without skill  | 57%       |

## Install

```bash
task install
```

This symlinks the skill into `~/.claude/skills/` so it's available globally. Alternatively, copy `.claude/skills/taskfile/` into any project's `.claude/skills/` directory for project-scoped use.

## Project structure

```
.claude/skills/taskfile/SKILL.md  # The skill prompt
.claude/skills/taskfile/lint.sh   # Structural lint (run by LLM after generating)
Taskfile.yml                      # Thin orchestrator
.taskfiles/dev.yml                # Dev module (test, lint)
.taskfiles/eval.yml               # LLM eval module (requires Claude CLI)
scripts/install.sh                # Skill installer (called by task install)
tests/ci.venom.yml                # CI test suite (Venom)
tests/fixtures/                   # Good and bad Taskfile fixtures
evals/evals.venom.yml             # LLM eval suite (Venom)
evals/lib/eval-run.yml            # Venom user executor for per-eval logic
evals/evals.json                  # 10 structured LLM eval cases
.github/workflows/ci.yml          # GitHub Actions CI pipeline
```

## Testing

```bash
# Run CI-safe tests (lint + fixtures + parse checks)
task test

# Run lint only
task lint

# Run all CI-safe quality gates (lint + test)
task check
```

The CI test suite (`tests/ci.venom.yml`) validates:

- **Self-lint** — the project's own Taskfile.yml passes the lint script
- **Task parse** — root Taskfile.yml and modules parse without errors
- **Good fixtures** — known-correct Taskfiles pass all lint checks
- **Bad fixtures** — failure scenarios (missing version, bare includes, wrong `default` position, ad-hoc names, missing `check` task, wrong file extension, wrong module directory, etc.) are correctly detected

Tests use [Venom](https://github.com/ovh/venom) as the test runner.

## LLM evals

LLM evals require the Claude CLI and are not part of CI.

```bash
# Run all LLM evals
task eval:test

# Run a single eval by ID
task eval:run -- 2

# List eval cases
task eval:list
```

Eval results go to `.test-output/` (override with `TEST_DIR`). Results are in Venom's XML format.

## Triggering note

This skill is a convention-enforcement skill. Claude can create Taskfiles without it, so the skill description alone won't trigger automatic loading. Install it at the project level (`.claude/skills/`) where it loads automatically, rather than relying on description-based triggering.

## License

MIT
