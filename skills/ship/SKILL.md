---
name: ship
description: Use when ready to commit, push, and open a pull request in any git repo — validates, commits, pushes, and opens the PR
user-invocable: true
allowed-tools: Bash, Read, Edit, Glob, Skill
arguments:
  - name: message
    description: "Optional commit message override"
    required: false
---

# Ship Skill

Pre-flight → commit → push → PR. Runs all checks and fixes before touching the remote.

Read the repo's own CLAUDE.md/AGENTS.md first. Branch prefixes, PR base branch, and commit
format are per-repo, and the repo's checked-in instructions win over anything below.

## Pre-Flight

### 1. Branch guard

```bash
git branch --show-current
```

- On a base branch (`main`, `dev`, or whatever the repo's instructions name): STOP. Create a
  feature branch first, using a prefix the repo actually lists, named for the work in hand.

### 2. Rebase on the base branch

The PR base is the one in the repo's instructions; if none is stated, the GitHub default branch
(`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`). Below, `<base>` is that branch.

```bash
git fetch origin
git rebase origin/<base>
```

- Conflicts: resolve file by file, then `git rebase --continue`.
- Never `git rebase --skip` or `--abort` without telling the user.

### 3. Validate

Use whatever the repo really verifies with, in order of preference:

1. `.pre-commit-config.yaml` present → run the `pre-commit-fix` skill (always `--all-files`).
2. The checks in the repo's instructions, `Taskfile.yml`/`Makefile`, or `package.json` scripts
   (build, test, lint, vet, `terraform validate`, `ansible-lint`, ...).
3. None defined → skip.

Fix every failure and re-run until clean. Never report a check as passing without its output.
If the loop runs more than 5 iterations without converging, stop and ask.

### 4. Hardcoded secret scan

```bash
git diff origin/<base>...HEAD | grep -E '^\+.*"[A-Za-z0-9+/]{20,}"|password\s*=\s*"[^{]|token\s*=\s*"[^{]|secret\s*=\s*"[^{'
```

- Any match: flag it to the user and stop. Do NOT open the PR.
- References to a secret manager or env lookup are fine.

### 5. Clean up gone branches

```bash
git fetch --prune
git branch -vv | grep ': gone]'
```

Delete those local branches with `git branch -d`; use `-D` only if `-d` fails and the branch is
clearly merged. Never delete the branch you are shipping.

## Commit & Push

1. Stage explicitly — the files you changed plus any the hooks regenerated. Never `git add -A`,
   and never stage secrets/env files (`.env*`, `.envrc`, `*.tfvars`, vault files, private keys).
2. Commit with the repo's convention (`<type>: <summary>` and a short bullet body if the repo has
   none). Where the prefix drives release versioning, choose it deliberately rather than
   defaulting to `chore`. Use `{{message}}` if provided. If hooks fail, fix and retry — never
   `--no-verify`.
3. Push: `git push -u origin <branch>`. If rejected, investigate before force-pushing.

## Create the PR

```bash
gh pr create --base <base> --title "<title>" --body "<body>"
```

Body: a `## Summary` of bullets, a `## Test Plan` checklist, and the pre-flight results. Follow any
PR template the repo ships. Print the PR URL.

If the repo's instructions say an automated reviewer (e.g. CodeRabbit) reviews on GitHub, do not
also run it locally — address its comments afterwards with `/fix-pr`.

## After the PR

Tell the user the PR is open and the branch is ready for testing. Do NOT delete the local branch
yet — they may need it for testing or follow-up fixes. Delete it only once they confirm testing is
done or ask for cleanup (`git checkout <base> && git branch -d <branch>`).

## Rules

- NEVER skip pre-flight, use `--no-verify`, or commit directly to a base branch.
- NEVER proceed if hardcoded secrets are detected.
- Repo-specific rules (protected files, extra checks) live in the repo's instructions, not here.
