---
name: log-analysis
description: Analyse the logs produced by a maven-upgrade-java-spring-boot run (identified by <timestamp> and <module-name>) and produce a human-readable report. When the run failed, the report includes concrete mitigation actions to remediate the issue.
---

# log-analysis

Reads every `.log` file produced by a **maven-upgrade-java-spring-boot** run and
produces a consolidated report. When `overallStatus` is `FAILED`, the report
must include targeted **mitigation actions**.

## Inputs

| Input         | Required | Notes |
|---------------|----------|-------|
| `timestamp`   | yes      | The `yyyyMMdd-HHmmss` value computed by the upgrade run |
| `module-name` | yes      | `.` (root) or the module that was upgraded |

The run directory is:

```
maven-upgrade-java-spring-boot/<timestamp>/<module-label>/
```

where `<module-label>` is `root` for `.`, otherwise the module name with `/`
replaced by `-`.

## Steps

1. **Collect the logs** using the helper script (prints `run.log` plus a tail of
   every `*.log`):

   ```bash
   bash .github/skills/log-analysis/scripts/collect-logs.sh \
     --timestamp "<timestamp>" \
     --module-name "<module-name>" \
     --base-dir "$(pwd)"
   ```

2. **Parse `run.log`** to determine `overallStatus`, `runId`, and the per-step
   `status` map (`orchestrator`, `preflight`, `execute-rewrite`, `maven-build`).

3. **Read the per-step logs** referenced in `run.log`:
   - `preflight.log` / `pre-flight-error.log`
   - `execute-rewrite.log`
   - `maven-build.log`
   - `orchestrator.log`

4. **Produce the report** and write it to:

   ```
   maven-upgrade-java-spring-boot/<timestamp>/<module-label>/report.md
   ```

   The report must contain:
   - **Summary**: runId, timestamp, module, target Java/Spring Boot versions,
     and `overallStatus`.
   - **Step results table**: each step → SUCCESS / FAILED / not-reached.
   - **Key findings**: notable warnings/errors extracted from the logs.
   - **Mitigation actions** (only when `overallStatus == FAILED`): see below.

## Mitigation guidance (when `overallStatus == FAILED`)

Identify the first failed step and map the symptom to an action:

- **preflight FAILED** — inspect `pre-flight-error.log`.
  - Invalid `java-version` → use one of `17`, `21`, `25`.
  - Invalid `spring-boot-version` → use one of `3.5`, `4.0`.
  - Module not found → use `.` for the root, or a `<module>` declared in the
    root `pom.xml`; confirm the module has its own `pom.xml`.

- **execute-rewrite FAILED** — inspect `execute-rewrite.log`.
  - Recipe/artifact resolution errors → check network access to Maven Central
    and that the recipe coordinates resolve; pin a concrete
    `rewrite-maven-plugin` version if `RELEASE` is unavailable.
  - "recipe not found" for the chosen versions → confirm the recipe IDs exist in
    the resolved `rewrite-spring` / `rewrite-migrate-java` versions.
  - Out-of-memory / long runs → increase `MAVEN_OPTS` heap (`-Xmx`).

- **maven-build FAILED** — inspect `maven-build.log`.
  - Compilation errors after the rewrite → review the OpenRewrite changes; some
    APIs removed in the new Spring Boot/Java version may need manual migration.
  - Dependency convergence / version conflicts → align managed versions with the
    new Spring Boot BOM.
  - Test failures → triage failing tests introduced by behavioural changes.
  - Toolchain mismatch → ensure a JDK matching `java-version` is installed and
    selected (e.g. via `.sdkmanrc` / toolchains).

- **timeout (rc=124 in orchestrator.log)** — the step exceeded the wait budget;
  re-run, or confirm the background Maven process is still progressing.

End the report with the exact commands to re-run the pipeline after applying the
mitigation.
