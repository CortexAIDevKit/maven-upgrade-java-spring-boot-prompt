# maven-upgrade-java-spring-boot-prompt

GitHub copilot prompt to upgrade java and spring-boot

## What this prompt does ?

This is a **GitHub Copilot Prompt**. Copilot Chat in VS Code discovers it via
`.github/prompts/maven-upgrade-java-spring-boot.prompt.md` and runs it in `agent`
mode using `gpt-5.3-codex`.

Fill in the persona, execution order, hard constraints, and output expectations
in the prompt file to define the behavior.

## Structure

```
maven-upgrade-java-spring-boot-prompt/
└── .github/
    ├── prompts/
    │   └── maven-upgrade-java-spring-boot.prompt.md   # The prompt Copilot runs
    └── instructions/
        └── prompts.instructions.md       # Conventions applied to prompt files
```

- **`maven-upgrade-java-spring-boot.prompt.md`** — frontmatter (name, description, agent,
  model, tools, authors) plus sections for persona/goal, execution order,
  hard constraints, and output expectations.
- **`prompts.instructions.md`** — repository conventions auto-applied by
  Copilot when editing files under `.github/prompts/`.


## Invoking from Copilot

Open Copilot Chat in VS Code and invoke the prompt by name:

```
/maven-upgrade-java-spring-boot
```

Or reference it with a trigger phrase that matches its description.
