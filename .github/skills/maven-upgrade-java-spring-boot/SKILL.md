---
name: "maven-upgrade-java-spring-boot"
description: "Skill to upgrade java and spring-boot"
argument-hint: "application-id (required), module-name (optional), java-version (optional), spring-boot-version (optional)"
---

# Maven Upgrade Java Spring Boot Skill

This skill orchestrates Maven-based Java and Spring Boot upgrades with
validated inputs, timestamped run artifacts, and non-blocking OpenRewrite
execution.

## Inputs

- `application-id` (required)
- `module-name` (optional, defaults to `.`)
- `java-version` (optional, defaults to `25`)
- `spring-boot-version` (optional, defaults to `4.0`)
- `timestamp` (optional externally, otherwise computed once by orchestrator in
  format `yyyyMMdd-HHmmss`)

## Execution

Run this from the repository root after replacing the placeholders with your actual values:

```bash
bash .github/skills/maven-upgrade-java-spring-boot/scripts/orchestrator.sh \
  --application-id "<application-id>" \
  --module-name "<module-name>" \
  --java-version "<java-version>" \
  --spring-boot-version "<spring-boot-version>"
```


## Artifacts

Per run artifacts are stored at:

`maven-upgrade-java-spring-boot/<timestamp>/<module-name>/`

Files:

- `run.log`
- `orchestrator.log`
- `preflight.log`
- `execute-rewrite.log`
- `pre-flight-error.log` (on pre-flight failures)

## run.log Schema

```json
{
  "runId": "<unique identifier>",
  "timestamp": "<yyyyMMdd-HHmmss>",
  "overallStatus": "STARTED|IN-PROGRESS|FAILED|COMPLETED",
  "status": {
    "orchestrator": "SUCCESS|FAILED",
    "preflight": "SUCCESS|FAILED",
    "execute-rewrite": "SUCCESS|FAILED"
  },
  "log": {
    "orchestrator": "maven-upgrade-java-spring-boot/<timestamp>/<module-name>/orchestrator.log",
    "preflight": "maven-upgrade-java-spring-boot/<timestamp>/<module-name>/preflight.log",
    "execute-rewrite": "maven-upgrade-java-spring-boot/<timestamp>/<module-name>/execute-rewrite.log"
  }
}
```

## Suggested Invocation

```bash
bash .github/skills/maven-upgrade-java-spring-boot/scripts/orchestrator.sh \
  --application-id "my-app" \
  --module-name "." \
  --java-version "25" \
  --spring-boot-version "4.0"
```