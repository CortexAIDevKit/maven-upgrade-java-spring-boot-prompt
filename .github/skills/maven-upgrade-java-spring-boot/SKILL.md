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

## Scripts

All scripts are under `.github/skills/maven-upgrade-java-spring-boot/scripts`.

1. `orchestrator.sh`
   - Computes defaults and timestamp once.
   - Initializes run artifacts and `run.log`.
   - Calls `pre-flight.sh`.
   - Calls `execute-rewrite.sh` in non-blocking mode.
   - Maintains `run.log` status and log pointers.

2. `pre-flight.sh`
   - Validates:
     - Java version in `{17, 21, 25}`
     - Spring Boot version in `{3.5, 4.0}`
     - module name is `.` or listed in root `pom.xml` modules
     - target module has a valid `pom.xml`
   - Writes validation output to `preflight.log`.
   - On failure writes `pre-flight-error.log` and exits non-zero.

3. `execute-rewrite.sh`
   - Launches `mvn rewrite:run` against root module or selected module.
   - Supports single-module and multi-module projects.
   - Runs asynchronously and returns immediately.
   - Writes launch/runtime details to `execute-rewrite.log`.

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