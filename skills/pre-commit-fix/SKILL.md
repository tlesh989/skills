---
name: pre-commit-fix
description: Run pre-commit, stage auto-generated changes, re-run until clean
---
1. Run `pre-commit run --all-files`
2. If hooks modified files (terraform_docs, prettier, etc.), `git add -A`
3. Re-run until exit 0 or a real lint error appears
4. Report any non-auto-fixable failures to user
