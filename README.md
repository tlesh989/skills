# skills

Personal Claude Code skills: `ship`, `fix-pr`, `pre-commit-fix`, `context-audit`, `settled`.

## Install

```bash
git clone https://github.com/tlesh989/skills ~/repos/tlesh989/skills
~/repos/tlesh989/skills/install.sh                       # $CLAUDE_CONFIG_DIR or ~/.claude
~/repos/tlesh989/skills/install.sh ~/.claude-personal ~/.claude-work
```

Skills are symlinked, so `git pull` updates every profile. Existing real directories are skipped;
`-f` moves them to `<config_dir>/skills-backup/<name>` and links the repo version.

Repo-specific rules (protected files, extra checks) belong in each project's CLAUDE.md, not here.
