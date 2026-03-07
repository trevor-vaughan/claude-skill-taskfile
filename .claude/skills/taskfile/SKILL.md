---
name: taskfile
description: Conventions and templates for creating, editing, refactoring, or extending Taskfile.yml and .taskfiles/ module files (https://taskfile.dev). ALWAYS use this skill when the user mentions Taskfile, Taskfile.yml, task runner, task tasks, .taskfiles, or asks to set up task automation using Task (taskfile.dev). Also trigger when converting a Makefile or Justfile to Task, adding tasks or includes to an existing Taskfile.yml, or when the user says "task" in the context of build/task automation (not the English word). This includes casual requests like "set up a taskfile", "add a task", "create a taskfile module", or "nuke task". If the request involves taskfile.dev in any way, use this skill.
---

# Taskfile Skill

## COMMON MISTAKES — do NOT do these

These are patterns the model often generates incorrectly. Check your output against this list.

| WRONG                                                              | RIGHT                                                                                |
|--------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| `taskfile.yml` or `Taskfile.yaml`                                  | `Taskfile.yml` (capital T, `.yml` extension)                                         |
| Include file at `tasks/foo.yml` or alongside root                  | Include file at `.taskfiles/foo.yml`                                                 |
| `cmd: task other:task` (subprocess)                                | `task: other:task` (internal call, preserves context)                                |
| Passing args via `cmd: task name -- {{.CLI_ARGS}}`                 | Internal `task:` call with `vars:` map                                               |
| Task without `desc:` that should be public                         | Every public task gets a `desc:` field                                               |
| `internal: true` to hide from listing                              | Omit `desc:` to hide from `--list` (still callable); `internal: true` blocks CLI invocation entirely (other tasks can still call it) |
| Flat root Taskfile with domain tasks                               | Extract includes by domain concern when project has multiple concerns                |
| Include named after a tool (`psql.yml`)                            | Include named after a concern (`db.yml`)                                             |
| Test tasks in `docker.yml` because tests run in a container        | Test tasks in `test.yml` — classify by purpose, not implementation                   |
| Root task duplicates include logic                                 | Root shortcut delegates via `deps:` or `cmds: [{task: "mod:task"}]`                  |
| Ad-hoc task names (`run-tests`, `do-lint`)                         | Standard names: `test`, `lint`, `build`, `dev`, `fmt`, `check`                       |
| Bare `{{.CLI_ARGS}}` without fallback in included tasks            | Use `ARGS` var with fallback: `{{.ARGS \| default .CLI_ARGS}}`                       |
| Colons in unquoted YAML values                                     | Escape colons or use `cmd:` form with template trick                                 |
| `{{ .VAR }}` with spaces in template                               | `{{.VAR}}` — no whitespace inside braces (Go template convention)                    |
| `binary_name` or `myVar` in vars                                   | `BINARY_NAME` — UPPERCASE for all variable names                                     |
| `do_something` (snake_case task name)                               | `do-something` — kebab-case for task names                                           |
| `version: 2` or missing version                                    | `version: '3'` (quoted string) as the first line                                    |
| Long shell script in `cmd: \|` block (>5 lines)                    | Extract to `scripts/<name>.sh` and call `bash {{.ROOT_DIR}}/scripts/<name>.sh`       |

## MANDATORY RULES — apply to EVERY file you create or edit

These rules are non-negotiable. Violating any of them is a bug you must fix.

1. The root file MUST be named `Taskfile.yml` (capital T, `.yml` extension).
2. EVERY file (root `Taskfile.yml` AND every `.taskfiles/*.yml` include) MUST start with:
   ```yaml
   version: '3'
   ```
3. EVERY file MUST have `default` as its first task:
   ```yaml
   tasks:
     default:
       desc: List all available tasks
       silent: true
       cmd: task --list
   ```
4. Section order in every file: `version` → `includes` → `vars` → `dotenv` → `tasks`.
5. Include files MUST live at `.taskfiles/<name>.yml` — never `tasks/`, never alongside the root Taskfile.yml.
6. Import includes with explicit taskfile path:
   ```yaml
   includes:
     docker:
       taskfile: .taskfiles/docker.yml
   ```
   Never use bare string includes.
7. Use `vars:` with defaults for variables:
   ```yaml
   vars:
     APP_NAME: '{{.APP_NAME | default "myapp"}}'
   ```
8. Every public task gets a `desc:` field describing what it does.
9. Parameterized tasks document variables in the `desc:` or with a comment above the task.
10. Private/helper tasks omit `desc:` (hidden from `--list`, still callable). Do NOT use `internal: true` unless you want to block direct invocation entirely.
11. Dependencies use the `deps:` field:
    ```yaml
    check:
      desc: Run all quality gates
      deps: [lint, test]
    ```
12. Destructive tasks use `prompt:` for confirmation; `desc:` includes "DESTRUCTIVE":
    ```yaml
    destroy:
      desc: Tear down everything — DESTRUCTIVE
      prompt: This will destroy everything. Are you sure?
      cmd: echo "Destroying..."
    ```
13. For multi-concern projects, extract includes by domain concern. Name includes after the concern (`db.yml`), not the tool (`psql.yml`). The root Taskfile.yml should be a thin orchestrator with only `default`, shortcut tasks, and project-wide tasks like `check` or `clean`.
14. Root Taskfile.yml with includes should provide shortcut tasks for common workflows that delegate to included tasks, so developers get a flat namespace for everyday tasks.
15. Use the standard task names (`dev`, `test`, `build`, `lint`, `fmt`, `check`, `clean`) as the root Taskfile.yml's public API — see the vocabulary table below. Never use ad-hoc alternatives like `run-tests`, `do-lint`, `compile`, or `format`.
16. In included files, use `{{.ROOT_DIR}}` to reference project root paths. Never use bare relative paths — included task working directories may differ from the project root.
17. Use internal `task:` calls (not `cmd: task`) to call other tasks. Subprocess calls lose `USER_WORKING_DIR` context.
18. For argument passthrough in included tasks, define a custom `ARGS` variable with a CLI_ARGS fallback:
    ```yaml
    vars:
      ARGS: '{{.ARGS | default .CLI_ARGS}}'
    ```
    The calling task passes args via `vars:`:
    ```yaml
    cmds:
      - task: module:task-name
        vars:
          ARGS: '{{.CLI_ARGS}}'
    ```
19. Extract inline scripts longer than ~5 lines to `scripts/` files. Taskfiles should stay declarative — long shell blocks are hard to read, can't be linted by shellcheck, and can't be tested independently. Put scripts in `scripts/` at the project root (or `{{.ROOT_DIR}}/scripts/` from includes) and call them:
    ```yaml
    deploy:
      desc: Deploy the application
      cmd: bash "{{.ROOT_DIR}}/scripts/deploy.sh" {{.ENV}}
    ```

## STANDARD TOP-LEVEL TASKS — consistent developer ergonomics

Every project should expose a predictable set of top-level task names. A developer should be able to run `task test`, `task dev`, or `task check` in any project without guessing.

### The standard vocabulary

| Task    | Purpose                                                  | Include when                      |
|---------|----------------------------------------------------------|-----------------------------------|
| `dev`   | Start development environment (server, watch mode, REPL) | Project has a dev loop            |
| `test`  | Run the test suite                                       | Always (every project has tests)  |
| `build` | Build or compile the project                             | Project has a build/compile step  |
| `lint`  | Run linters                                              | Project has linters configured    |
| `fmt`   | Format code                                              | Project has formatters configured |
| `check` | Run **all** quality gates (lint + test + format-check)   | Always                            |
| `clean` | Remove build artifacts, caches, generated files          | Project produces build output     |

### Rules for standard tasks

- **Use these exact names.** Do not invent alternatives like `run-tests`, `do-lint`, `compile`, or `format`.
- **`check` is the meta-task.** It should depend on the applicable quality gates: `deps: [lint, test]`. Add `fmt` checks as appropriate.
- Standard tasks live in the root Taskfile.yml as shortcuts delegating to includes.
- **Only include what applies.** A static site with no tests skips `test`. A script project with no build step skips `build`. Don't add empty stubs.

## NAMESPACING — separation of concerns with includes

### When to extract includes

- **Use includes for multi-concern projects.** When a project has tasks spanning different domains (e.g., docker + database + CI), organize them into includes by concern.
- **Single-concern projects may use a single `dev.yml` include** — even a Go project with only build/test/lint/fmt benefits from the thin-root pattern. The root stays a consistent entry point.
- The root Taskfile.yml is a **thin orchestrator**: project-wide variables, include imports, and shortcut tasks that delegate to includes.
- The only tasks that live directly in the root Taskfile.yml are `default`, shortcut tasks (that delegate to included tasks), and truly project-wide tasks like `clean` or `check`.

### How to identify concerns — READ CAREFULLY

Group by **domain**, not by tool. A concern is a cluster of tasks that share context (variables, targets, lifecycle).

**Decision rule: classify by purpose, not implementation.** Ask "what does this task *accomplish*?" not "what tool does it *use*?" A test that runs inside Docker is a *testing* task, not a *Docker* task. A database migration that uses kubectl is a *database* task, not a *Kubernetes* task. The tool is an implementation detail; the concern is the developer intent.

| Concern              | Include       | Typical tasks                       |
|----------------------|---------------|-------------------------------------|
| Development workflow | `dev.yml`     | build, test, lint, fmt, bench       |
| Testing              | `test.yml`    | run, list, watch, coverage          |
| Containers           | `docker.yml`  | build, push, run, compose-up        |
| CI/CD                | `ci.yml`      | lint, deploy, release               |
| Database             | `db.yml`      | migrate, seed, reset, dump, restore |
| Infrastructure       | `infra.yml`   | plan, apply, destroy                |
| Kubernetes           | `k8s.yml`     | apply, diff, rollback, logs         |
| Documentation        | `docs.yml`    | build, serve, publish               |

For single-concern projects (e.g., a Go or Rust project with only build/test/lint/fmt), use a single `dev.yml` include. The root Taskfile.yml still stays thin with shortcuts.

### Root Taskfile.yml as orchestrator

The root Taskfile.yml should be a **thin entry point**:

1. **Project-wide variables** — shared across concerns (app name, environment).
2. **Include imports** — one include per concern.
3. **Shortcut tasks** — high-level developer workflows that delegate to included tasks.

Shortcut tasks provide a flat namespace for common tasks so developers don't need to know the include structure for everyday work:

```yaml
tasks:
  build:
    desc: Build the project (shortcut)
    cmds:
      - task: docker:build

  check:
    desc: Run all quality gates
    deps: [lint, test]
```

### Include self-containment

Each include should be independently understandable:

- Own variables (with defaults) for its domain.
- No cross-include task dependencies — includes depend only on their own tasks and private helpers.
- Own `default` task listing its own tasks.

## USEFUL TASKFILE FEATURES

### Incremental builds with `sources:` / `generates:`

Skip tasks when inputs haven't changed. This is critical for build tasks to avoid redundant work:

```yaml
build:
  desc: Build the binary
  sources:
    - ./**/*.go
    - go.mod
  generates:
    - bin/app
  cmd: go build -o bin/app ./cmd/app
```

Use `method: checksum` (default) for content-based checks or `method: timestamp` for speed.

### Preconditions

Fail early with a clear message when prerequisites aren't met:

```yaml
deploy:
  desc: Deploy to production
  preconditions:
    - sh: command -v kubectl
      msg: "kubectl is required — install it first"
    - sh: test -f kubeconfig.yml
      msg: "kubeconfig.yml not found"
  cmd: kubectl apply -f manifests/
```

### Run deduplication

Prevent shared dependency tasks from running multiple times:

```yaml
setup:
  run: once
  cmd: npm install
```

Use `run: once` for tasks that appear as dependencies of multiple other tasks (e.g., `setup` depended on by both `test` and `build`).

### Required variables

Validate that variables are set before execution:

```yaml
deploy:
  desc: Deploy to an environment
  requires:
    vars: [ENV, VERSION]
  cmd: deploy --env {{.ENV}} --version {{.VERSION}}
```

## Template: root Taskfile.yml

When creating a Taskfile.yml, start by copying this template and adapting it. For projects with includes, the root Taskfile.yml acts as a thin orchestrator — project-wide variables, imports, and shortcut tasks that delegate to includes.

```yaml
version: '3'

includes:
  dev:
    taskfile: .taskfiles/dev.yml

vars:
  APP_NAME: '{{.APP_NAME | default "myapp"}}'

tasks:
  default:
    desc: List all available tasks
    silent: true
    cmd: task --list

  test:
    desc: Run tests (shortcut)
    cmds:
      - task: dev:test

  lint:
    desc: Run linters (shortcut)
    cmds:
      - task: dev:lint

  build:
    desc: Build the project (shortcut)
    cmds:
      - task: dev:build

  check:
    desc: Run all quality gates
    deps: [lint, test]

  clean:
    desc: Remove build artifacts
    cmd: rm -rf bin/ dist/
```

## Template: include file at `.taskfiles/<name>.yml`

Include files follow the SAME structure. They MUST have `version: '3'` and their own `default`. Use `{{.ROOT_DIR}}` for absolute paths to project files (included task working directories may differ from the project root). Here is an example `.taskfiles/docker.yml`:

```yaml
version: '3'

vars:
  REGISTRY: '{{.REGISTRY | default "ghcr.io/myorg"}}'
  IMAGE: '{{.IMAGE | default "myapp"}}'
  TAG: '{{.TAG | default "latest"}}'

tasks:
  default:
    desc: List tasks in this module
    silent: true
    cmd: task docker --list

  build:
    desc: Build the Docker image
    cmd: docker build --target {{.TARGET | default "production"}} -t {{.REGISTRY}}/{{.IMAGE}}:{{.TAG}} .

  push:
    desc: Push the image to the registry
    deps: [build]
    cmd: docker push {{.REGISTRY}}/{{.IMAGE}}:{{.TAG}}

  run:
    desc: Run the container locally
    cmd: docker run --rm {{.CLI_ARGS}} {{.REGISTRY}}/{{.IMAGE}}:{{.TAG}}
```

## Automated lint — run AFTER every file you create or edit

A lint script validates all deterministic structural rules. Run it after creating or editing any Taskfile.yml or `.taskfiles/*.yml` include, and fix every failure before finishing:

```bash
bash .claude/skills/taskfile/lint.sh .
```

The script checks: file naming, `version: '3'`, `default` as first task, `desc:` on public tasks, explicit include paths, section order, standard task names, subprocess calls, and `check` meta-task presence. Any `FAIL` output is a bug — fix it and re-run until all checks pass.

If the lint script is not available at `.claude/skills/taskfile/lint.sh`, check `~/.claude/skills/taskfile/lint.sh`.

## Manual checklist — judgment calls the linter cannot make

After the lint passes, verify these by inspection:

- [ ] Tasks are organized into includes by domain concern (purpose, not implementation tool)
- [ ] Includes are named after concerns, not tools (e.g., tests that run in Docker belong in `test.yml`, not `docker.yml`)
- [ ] Root Taskfile.yml with includes has shortcut tasks for common workflows
- [ ] Includes are self-contained — no cross-include task dependencies
- [ ] Included tasks use `{{.ROOT_DIR}}` paths, not bare relative paths
- [ ] Standard task names used where applicable (`dev`, `test`, `build`, `lint`, `fmt`, `check`, `clean`)
- [ ] Destructive tasks use `prompt:` and desc says "DESTRUCTIVE"
- [ ] Dependencies use the `deps:` field, not inline shell calls
- [ ] Internal `task:` calls used instead of `cmd: task` subprocess calls
- [ ] Build tasks use `sources:` / `generates:` where applicable
- [ ] Shared dependency tasks use `run: once` to avoid redundant execution
- [ ] Inline scripts longer than ~5 lines are extracted to `scripts/`
