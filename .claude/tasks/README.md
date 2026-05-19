# Task briefs

Each file in this directory is a **self-contained brief** that a fresh Claude Code session (or subagent dispatched via the `Agent` tool) can act on without any parent-conversation context.

## Convention

- Filename: `NNN-kebab-case-slug.md` (zero-padded to 3 digits)
- Must include sections: **Goal**, **Context**, **Steps**, **Acceptance**, **Out of scope**
- Reference specific file paths with line numbers when possible
- Capture *why* the work matters now — without context, fresh sessions can't make judgment calls
- When you add, close, or change a brief, update [`../CONDUCTOR.md`](../CONDUCTOR.md)'s open-task table

## How to dispatch

**From a fresh CLI session (external)**:
```
cd ~/Developer/here-ios
claude
# Paste the relevant task brief (or a handoff prompt that references it)
```

**Inline from the conductor chat (subagent)**: invoke `Agent` with the brief content as `prompt`.

The brief should give a cold reader everything they need. If you find yourself adding "see the previous conversation" — rewrite the brief.

## Closing a task

When work is merged or otherwise resolved:

1. Update CONDUCTOR.md status to `DONE` (or remove the row)
2. Either delete the brief, or move it to `tasks/done/` if there's reference value
