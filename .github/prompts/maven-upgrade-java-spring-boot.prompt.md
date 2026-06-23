---
model: GPT-5 mini (copilot)
agent: agent
tools: [execute, read, edit, search]
description: Upgrade a Maven module's Java and Spring Boot versions with OpenRewrite, build it, and produce a log-analysis report.
argument-hint: "module-name (optional), java-version (optional), spring-boot-version (optional)"
---

# Maven: Upgrade Java & Spring Boot

Upgrade a Maven project (single-module or multi-module) to the requested Java and
Spring Boot versions using OpenRewrite, validate it with a Maven build, and
produce a report.

## Inputs

Collect these inputs. Apply the default when the user leaves one empty.

- **module-name**: ${input:module-name:Module to upgrade (declared in root pom.xml). Leave empty for the root}
  - Required. If empty/not provided, use `.` (the root project).
- **java-version**: ${input:java-version:Target Java version (17, 21 or 25)}
  - Required. If empty/not provided, use `25`.
- **spring-boot-version**: ${input:spring-boot-version:Target Spring Boot version (3.5 or 4.0)}
  - Required. If empty/not provided, use `4.0`.

## Timestamp

Do **not** compute the timestamp yourself. `orchestrator.sh` computes a single
`<timestamp>` in the format `yyyyMMdd-HHmmss` and reuses it across every script.
After launching the run, read it back from the newest directory under
`maven-upgrade-java-spring-boot/` so you can pass the same `<timestamp>` to the
log-analysis step.

## What to do

1. **Run the upgrade skill** at
   [`.github/skills/maven-upgrade-java-spring-boot/SKILL.md`](../skills/maven-upgrade-java-spring-boot/SKILL.md).

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

   The orchestrator chains: **pre-flight → execute-rewrite → maven-build**,
   keeping `run.log` updated throughout.

2. **Resolve the run directory and timestamp**, then poll `run.log` until
   `overallStatus` is `COMPLETED` or `FAILED`:

   ```bash
   RUN_DIR="$(ls -1dt maven-upgrade-java-spring-boot/*/ | head -n1)"
   TIMESTAMP="$(basename "$RUN_DIR")"
   cat "${RUN_DIR}"*/run.log
   ```

3. **Run the log-analysis skill** at
   [`.github/skills/log-analysis/SKILL.md`](../skills/log-analysis/SKILL.md)
   with the resolved `<timestamp>` and the `<module-name>` to generate the
   report. When `overallStatus` is `FAILED`, the report must include mitigation
   actions.

4. **Report back** to the user: the per-step status from `run.log`, the location
   of the generated `report.md`, and a short summary (plus next steps if the run
   failed).
