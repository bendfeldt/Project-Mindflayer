---
name: promote-skill
description: Generalize a proven repository skill and promote its complete directory into the toolkit.
---

# Promote Skill

Read [promotion mechanics](references/promotion.md).

1. Resolve source and destination from repository context or ask; never assume a personal checkout path.
2. Copy the complete skill tree, including `agents/`, `references/`, `scripts/`, and assets.
3. Remove client-specific values and hardcoded local paths.
4. Keep `SKILL.md` frontmatter to `name` and `description`.
5. Add or update `agents/openai.yaml`.
6. Add every distributable file to the central manifest and advance its skill lifecycle version there.
7. Preview the diff and request approval before writing. Never commit or publish automatically.
