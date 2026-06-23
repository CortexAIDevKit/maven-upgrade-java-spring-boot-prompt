---
name: maven-upgrade-java-spring-boot
description: Upgrade a Maven module's Java and Spring Boot versions using OpenRewrite, then validate with a Maven build. Performs a pre-flight check, runs `mvn rewrite:run`, runs `mvn clean install`, and records a structured run.log for every run.
argument-hint: "module-name (optional), java-version (optional), spring-boot-version (optional)"
---

# maven-upgrade-java-spring-boot

Automates upgrading the **Java** and **Spring Boot** versions of a Maven project
(single-module or multi-module) using [OpenRewrite](https://docs.openrewrite.org/),
and validates the result with a Maven build.

## Inputs

| Input                 | Required | Default | Allowed values |
|-----------------------|----------|---------|----------------|
| `module-name`         | yes      | `.`     | `.` (root) or a module declared in the root `pom.xml` |
| `java-version`        | yes      | `25`    | `17`, `21`, `25` |
| `spring-boot-version` | yes      | `4.0`   | `3.5`, `4.0` |

A **timestamp** in the format `yyyyMMdd-HHmmss` is computed **once per run** by
`orchestrator.sh` and reused by every downstream script so that one run shares a
single output directory.

## Output layout

```
maven-upgrade-java-spring-boot/<timestamp>/<module-label>/
├── run.log                   # structured JSON status (single source of truth)
├── run.state                 # internal KEY=VALUE side-car (do not edit)
├── rewrite.yml               # generated OpenRewrite config (consolidated recipes)
├── artifact-coordinates.txt  # generated, de-duplicated recipe artifact coordinates
├── orchestrator.log
├── preflight.log
├── pre-flight-error.log      # validation errors only
├── execute-rewrite.log
└── maven-build.log
```

`<module-label>` is the module name with `/` replaced by `-`; the root module
(`.`) is labelled `root`.

### run.log shape

```json
{
  "runId": "20260621-141502-12345-678",
  "timestamp": "20260621-141502",
  "overallStatus": "STARTED | AT_PRE_FLIGHT | AT_EXECUTE_REWRITE | AT_MAVEN_BUILD | COMPLETED | FAILED",
  "status": {
    "orchestrator":    "SUCCESS | FAILED",
    "preflight":       "SUCCESS | FAILED",
    "execute-rewrite": "SUCCESS | FAILED",
    "maven-build":     "SUCCESS | FAILED"
  },
  "log": {
    "orchestrator":    "maven-upgrade-java-spring-boot/<timestamp>/<module-label>/orchestrator.log",
    "preflight":       "maven-upgrade-java-spring-boot/<timestamp>/<module-label>/preflight.log",
    "execute-rewrite": "maven-upgrade-java-spring-boot/<timestamp>/<module-label>/execute-rewrite.log",
    "maven-build":     "maven-upgrade-java-spring-boot/<timestamp>/<module-label>/maven-build.log"
  }
}
```

## Workflow

The pipeline is **chained**: `pre-flight → execute-rewrite → maven-build`. Each
long-running Maven step launches in the **background** (non-blocking) and writes
an `<step>.exit` sentinel on completion; the orchestrator waits on that sentinel
before starting the next step and keeps `run.log` up to date throughout.

1. **pre-flight** (`scripts/pre-flight.sh`) — validates the inputs:
   - `java-version` ∈ {17, 21, 25}
   - `spring-boot-version` ∈ {3.5, 4.0}
   - `module-name` is `.` or declared in the root `pom.xml` and has a parseable
     `pom.xml`. Errors are captured in `pre-flight-error.log`. Failure aborts
     the run with `overallStatus = FAILED`.
2. **execute-rewrite** (`scripts/execute-rewrite.sh`) — consolidates the
   per-version fragments under `resources/rewrite/{java,spring-boot}/<version>/`
   into a generated `rewrite.yml` and `artifact-coordinates.txt` in the run
   directory, then runs `mvn rewrite:run` against them
   (`-Drewrite.configLocation`). The generated `rewrite.yml` contains each
   source recipe plus a composition recipe whose `recipeList` is the
   de-duplicated union of all included recipes; that composition name is the
   active recipe, and the de-duplicated coordinates are the recipe artifacts.
   Non-blocking.
3. **maven-build** (`scripts/maven-build.sh`) — runs `mvn clean install` to
   validate the rewritten sources. Non-blocking.

All scripts handle failures gracefully and update `run.log` accordingly.

## How to run

The orchestrator is launched in the background so the agent is never blocked.
From the repository root:

```bash
chmod +x .github/skills/maven-upgrade-java-spring-boot/scripts/*.sh

nohup bash .github/skills/maven-upgrade-java-spring-boot/scripts/orchestrator.sh \
  --module-name "<module-name>" \
  --java-version "<java-version>" \
  --spring-boot-version "<spring-boot-version>" \
  --base-dir "$(pwd)" \
  > /dev/null 2>&1 &
```

Then determine the run directory (newest `<timestamp>`), and poll its `run.log`
until `overallStatus` is `COMPLETED` or `FAILED`:

```bash
RUN_DIR="$(ls -1dt maven-upgrade-java-spring-boot/*/ 2>/dev/null | head -n1)"
cat "${RUN_DIR}"/*/run.log
```

> Note: the orchestrator computes the `<timestamp>`. Capture it by reading the
> newest directory under `maven-upgrade-java-spring-boot/`, then pass the same
> `<timestamp>` and `<module-name>` to the **log-analysis** skill.

## Next step

When `overallStatus` is `COMPLETED` or `FAILED`, hand off to the
[`log-analysis`](../log-analysis/SKILL.md) skill with the run's `<timestamp>`
and `<module-name>` to produce the final report (including mitigation actions
when the run failed).
