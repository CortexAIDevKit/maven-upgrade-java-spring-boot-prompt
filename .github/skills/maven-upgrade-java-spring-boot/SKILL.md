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

## Suggested Invocation

```bash
bash .github/skills/maven-upgrade-java-spring-boot/scripts/orchestrator.sh \
  --application-id "my-app" \
  --module-name "." \
  --java-version "25" \
  --spring-boot-version "4.0"
```

## Hard constraints

Strict mode: execute only requested Execution, no extra validation, no assumptions, no follow-up actions without my explicit go-ahead.

Post-execution stop rule: once the orchestrator command returns, exit immediately. Do not run artifact checks, log reads, process polling, or any additional commands unless explicitly requested.