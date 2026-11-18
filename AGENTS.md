# AGENTS.md - Antigravity Quota Bar

## Offloading (`savings-bridge`)
- **Mandatory:** Follow `.agents/rules/local-llm.md` and the global `savings-bridge` skill (`~/.gemini/config/skills/savings-bridge/SKILL.md`) to offload eligible work and preserve primary Cloud quota.
- Use `savings-bridge` CLI (`~/.local/bin/savings-bridge`): run `savings-bridge models --json` first, then route atomic `ask`, `code`, `review`, `parse-json`, `git-commit`, and `git-changelog` slices (`-m free` / `-m glm-free` / `-m pickle` for non-sensitive work; `-m fast` / `-m coder` / `-m 7b` / `-m 14b` for local/secret-adjacent work).
- Never call `ollama run` or `localhost:11434` directly; never send `.env*`, keys, tokens, or secrets to external free cloud models.
- Keep architecture, multi-file wiring, complex debugging, sensitive diff review, and final build/test verification in the primary Cloud model.
