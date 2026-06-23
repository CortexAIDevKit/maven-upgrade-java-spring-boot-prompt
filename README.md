# maven-upgrade-java-spring-boot-prompt

GitHub Copilot prompt and skills to upgrade the **Java** and **Spring Boot**
versions of a Maven project using [OpenRewrite](https://docs.openrewrite.org/),
validate it with a Maven build, and produce a log-analysis report.

## What this does

This is a **GitHub Copilot Prompt** backed by two **skills**. Copilot Chat in
VS Code discovers the prompt via
`.github/prompts/maven-upgrade-java-spring-boot.prompt.md` and runs it in `agent`
mode using `GPT-5 mini`.

The prompt orchestrates the end-to-end flow:

1. **Run the upgrade skill** — launches `orchestrator.sh` in the background,
   which chains **pre-flight → execute-rewrite → maven-build** and keeps a
   structured `run.log` updated throughout.
2. **Resolve the run directory and timestamp**, then poll `run.log` until
   `overallStatus` is `COMPLETED` or `FAILED`.
3. **Run the log-analysis skill** — reads every `.log` from the run and writes a
   consolidated `report.md` (including mitigation actions when the run failed).
4. **Report back** with the per-step status, the `report.md` location, and a
   short summary.

## Inputs

All inputs are optional; defaults are applied when left empty.

| Input                 | Default | Allowed values                                        |
|-----------------------|---------|-------------------------------------------------------|
| `module-name`         | `.`     | `.` (root) or a module declared in the root `pom.xml` |
| `java-version`        | `25`    | `17`, `21`, `25`                                      |
| `spring-boot-version` | `4.0`   | `3.5`, `4.0`                                          |

A **timestamp** (`yyyyMMdd-HHmmss`) is computed **once per run** by
`orchestrator.sh` and reused by every downstream script, so a single run shares
one output directory.

## Structure

```
maven-upgrade-java-spring-boot-prompt/
└── .github/
    ├── prompts/
    │   └── maven-upgrade-java-spring-boot.prompt.md   # The prompt Copilot runs
    ├── instructions/
    │   └── prompts.instructions.md                    # Conventions for prompt files
    └── skills/
        ├── maven-upgrade-java-spring-boot/
        │   ├── SKILL.md
        │   ├── resources/rewrite/                     # OpenRewrite fragments
        │   │   ├── java/{17,21,25}/
        │   │   └── spring-boot/{3_5,4_0}/
        │   └── scripts/
        │       ├── orchestrator.sh                    # Chains the pipeline
        │       ├── pre-flight.sh                      # Validates inputs
        │       ├── execute-rewrite.sh                 # Consolidates recipes, runs rewrite:run
        │       ├── maven-build.sh                     # Runs mvn clean install
        │       └── common.sh                          # Shared helpers
        └── log-analysis/
            ├── SKILL.md
            └── scripts/
                └── collect-logs.sh                    # Collects run.log + log tails
```

## Skills

### `maven-upgrade-java-spring-boot`

Upgrades a Maven project (single- or multi-module) and validates it. The
pipeline is **chained** and each Maven step runs in the **background**
(non-blocking):

1. **pre-flight** — validates `java-version` ∈ {17, 21, 25},
   `spring-boot-version` ∈ {3.5, 4.0}, and that `module-name` is `.` or a module
   declared in the root `pom.xml`. Errors abort the run with
   `overallStatus = FAILED`.
2. **execute-rewrite** — consolidates the per-version fragments under
   `resources/rewrite/{java,spring-boot}/<version>/` into a generated
   `rewrite.yml` and de-duplicated `artifact-coordinates.txt`, then runs
   `mvn rewrite:run`.
3. **maven-build** — runs `mvn clean install` to validate the rewritten sources.

#### Output layout

```
maven-upgrade-java-spring-boot/<timestamp>/<module-label>/
├── run.log                   # structured JSON status (single source of truth)
├── run.state                 # internal KEY=VALUE side-car (do not edit)
├── rewrite.yml               # generated OpenRewrite config
├── artifact-coordinates.txt  # generated, de-duplicated recipe coordinates
├── orchestrator.log
├── preflight.log
├── pre-flight-error.log      # validation errors only
├── execute-rewrite.log
├── maven-build.log
└── report.md                 # written by the log-analysis skill
```

`<module-label>` is the module name with `/` replaced by `-`; the root module
(`.`) is labelled `root`.

### `log-analysis`

Reads every `.log` from a run (identified by `<timestamp>` and `<module-name>`)
and writes a consolidated `report.md` containing a summary, a per-step results
table, key findings, and — when `overallStatus == FAILED` — targeted
**mitigation actions** plus the exact commands to re-run the pipeline.

## Invoking from Copilot

Open Copilot Chat in VS Code and invoke the prompt by name:

```
/maven-upgrade-java-spring-boot
```

Or reference it with a trigger phrase that matches its description.

## Running the skills directly

From the repository root, make the scripts executable and launch the
orchestrator in the background (it must not block):

```bash
chmod +x .github/skills/maven-upgrade-java-spring-boot/scripts/*.sh

nohup bash .github/skills/maven-upgrade-java-spring-boot/scripts/orchestrator.sh \
  --module-name "<module-name>" \
  --java-version "<java-version>" \
  --spring-boot-version "<spring-boot-version>" \
  --base-dir "$(pwd)" \
  > /dev/null 2>&1 &
```

Resolve the run directory and poll `run.log` until `overallStatus` is
`COMPLETED` or `FAILED`:

```bash
RUN_DIR="$(ls -1dt maven-upgrade-java-spring-boot/*/ 2>/dev/null | head -n1)"
TIMESTAMP="$(basename "$RUN_DIR")"
cat "${RUN_DIR}"*/run.log
```

Then generate the report:

```bash
bash .github/skills/log-analysis/scripts/collect-logs.sh \
  --timestamp "$TIMESTAMP" \
  --module-name "<module-name>" \
  --base-dir "$(pwd)"
```
