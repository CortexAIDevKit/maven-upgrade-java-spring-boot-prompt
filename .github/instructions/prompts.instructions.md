---
description: "Use when creating or updating prompt, prompt metadata, or repository docs in this project. Enforces prompt naming, frontmatter completeness, and generated structure conventions from README.md."
applyTo: ".github/prompts/*.prompt.md"
---
# Copilot Instructions

These instructions apply to the entire repository. Follow them whenever you
author, edit, or extend a **GitHub Copilot Prompt** here.

## Repository purpose

This repository hosts one or more GitHub Copilot Prompts. Each prompt lives
under `.github/prompts/<prompt-name>.prompt.md` and is discovered by Copilot
agents in VS Code via its frontmatter.

The currently scaffolded prompt is **`maven-upgrade-java-spring-boot`** —
GitHub copilot prompt to upgrade java and spring-boot

## Prompt anatomy

Every prompt **must** follow this layout:

```
.github/prompts/<prompt-name>.prompt.md
```

The file has two parts:

- **Frontmatter** — `name`, `description`, `agent` (mode), `model`, `tools`,
  `authors`. Optional: `argument-hint`.
- **Body** — four required sections, in this order:
  1. **Persona / goal** — who the agent is and what it is trying to achieve.
  2. **Execution order** — the steps the agent should take.
  3. **Hard constraints** — what the agent must always or never do.
  4. **Output expectations** — the shape and content of the final answer.

## Naming convention

Prompt names follow **`<context>-<action>-<target>`**, all kebab-case.

| Segment   | Meaning                                    | Examples                                                                   |
|-----------|--------------------------------------------|----------------------------------------------------------------------------|
| `context` | Area, tech, or stage the prompt applies to | `maven`, `ci`, `repo`, `git`, `docs`, `test`, `security`, `api`, `angular` |
| `action`  | Imperative verb describing what it does    | `fix`, `generate`, `upgrade`, `debug`, `validate`, `create`, `scaffold`    |
| `target`  | The concrete artifact or problem           | `readme`, `workflow`, `dependencies`, `release-branch`, `unit-tests`       |

Rules for `target`:

- Be specific — prefer `legacy-java-code` over `code`, `cve-vulnerability`
  over `issue`.
- Use hyphens to compound — `release-branch`, `template-lint`, `unit-tests`.
- Match natural number — `dependencies` (plural), `readme` (singular).
- One logical target per prompt, even if it spans multiple words.

When proposing a new prompt, validate the name against this pattern **before**
creating files. The repository name is derived as `<prompt-name>-prompt`.

## Authoring rules

When creating or editing a prompt:

1. **One prompt, one job.** If a prompt does two things, split it.
2. **Frontmatter is complete.** `name`, `description`, `agent`, `model`,
   `tools`, and `authors` are all required. `description` is one line and
   should make the prompt's trigger condition obvious.
3. **Body sections are explicit and ordered** — Persona/goal, Execution
   order, Hard constraints, Output expectations. Do not invent extra
   top-level sections or omit required ones.
4. **Tools are minimal.** Declare only the tools the prompt actually uses
   in `tools:`. Default set: `codebase`, `search`, `editFiles`,
   `runCommands`.
5. **Mode matches intent.** Use `ask` for Q&A, `agent` for autonomous
   multi-step work, `plan` for proposing changes before applying them.
6. **Preserve placeholders.** When editing the template, keep Jinja
   placeholders (`{{ prompt_name }}`, etc.) intact unless the task
   explicitly asks to replace them.
7. **No hidden state.** Do not depend on env vars, network calls, or files
   outside the documented inputs.

## Copier question and derivation conventions

- `prompt_name` is derived as `{context}-{action}-{target}`.
- `repo_name` is derived as `{prompt_name}-prompt`.
- Keep question wording aligned with README terminology:
  - `context` = area / tech / stage
  - `action` = imperative verb
  - `target` = concrete artifact / problem

## Editing checklist

Before finishing a change, verify:

- [ ] Frontmatter is valid YAML and includes `name`, `description`, `agent`,
      `model`, `tools`, `authors`.
- [ ] All `todo:` markers in the prompt body have been resolved or
      intentionally left for the prompt author.
- [ ] The four body sections (Persona/goal, Execution order, Hard
      constraints, Output expectations) are present and in order.
- [ ] The prompt name still matches `<context>-<action>-<target>`.
- [ ] `repo_name` still matches `<prompt_name>-prompt`.

## Invoking from Copilot

Open Copilot Chat in VS Code and reference the prompt by name, or use a
trigger phrase that matches its `description` in the frontmatter.

## Documentation alignment

- Keep README examples consistent with the naming convention and Copier
  question definitions.
- If changing naming or structure behavior, update `README.md`, `copier.yml`,
  and the prompt template in the same change.
- Do not introduce alternative naming schemes unless explicitly requested.

## Out of scope

- Do **not** add CI, lint, or build infrastructure unless the prompt itself
  is about that.
- Do **not** introduce new top-level directories. Prompts belong under
  `.github/prompts/`.
- Do **not** edit generated files outside `.github/` without an explicit
  request.
