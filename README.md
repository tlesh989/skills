# skills

Personal Claude Code skills: `open-pr`, `fix-pr`, `pre-commit-fix`, `context-audit`, `settled`.

## Install

```bash
git clone https://github.com/tlesh989/skills ~/repos/tlesh989/skills
~/repos/tlesh989/skills/install.sh                       # $CLAUDE_CONFIG_DIR or ~/.claude
~/repos/tlesh989/skills/install.sh ~/.claude-personal ~/.claude-work
```

Skills are symlinked, so `git pull` updates every profile. Existing real directories are skipped;
`-f` moves them to `<config_dir>/skills-backup/<name>` and links the repo version.

Upgrading from `ship`: it was renamed to `open-pr`. Rerun `install.sh` for each profile to link
`open-pr`, then remove the old link by hand; the installer never removes links, so `ship` stays
behind as a broken symlink:

```bash
rm -f ~/.claude/skills/ship ~/.claude-personal/skills/ship   # list each profile you installed into
```

Repo-specific rules (protected files, extra checks) belong in each project's CLAUDE.md, not here.
