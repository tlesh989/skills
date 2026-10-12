---
name: fix-pr
description: Use when a PR has review comments to address — fetches CodeRabbit/human reviewer feedback for a PR, fixes valid issues, resolves skipped threads with reasons, and pushes
user-invocable: true
allowed-tools: Bash, Read, Edit, Glob, Grep, Agent
arguments:
  - name: pr
    description: "Optional PR number (defaults to the PR for the current branch)"
    required: false
---

# fix-pr — PR Review Fix Workflow

Fetch every review finding, triage, fix the valid ones, validate, push, answer the rest on-thread,
and post a summary. Stop only for destructive changes or before dismissing a human's review.

If this session carries unrelated prior context, consider `/clear` first. Skip that if continuing
work already in progress on this PR.

## Step 1 — Identify the PR and fetch all findings

Use the given PR number, else detect it:

```bash
gh pr view --json number,headRefName,baseRefName
```

- No open PR for the branch: STOP and tell the user.
- On a base branch (`main`, `dev`, ...): STOP — fixes belong on a feature branch.

Fetch (in parallel; owner/repo from `git remote get-url origin`):

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/reviews
gh api repos/{owner}/{repo}/pulls/<PR>/comments
gh api graphql -f query='query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
    reviewThreads(first:100){ nodes{ id isResolved comments(first:1){ nodes{ databaseId path } } } } } } }' \
  -F owner=<OWNER> -F repo=<REPO> -F pr=<PR>
```

Keep the `thread node ID → comment databaseId → file:line` mapping so each skipped finding can be
resolved on its thread in Step 5.

## Step 1b — When review is churning, get one full independent review

Bots like CodeRabbit review incrementally: each pass goes deep on the last push and never steps
back to the whole design. Count prior fix rounds
(`git log --oneline <base>..HEAD | grep -c 'address .*review'`) and note which sections they
touched. Run a full independent review now if **this is round 3 or later**, or **the section a
finding names was already flagged in an earlier round**.

How: spawn one read-only `general-purpose` Agent with a `model` different from this session's. No
edits, commits, or GitHub posts. Ask for one ranked pass over the whole PR, most severe first;
each finding gets lines, severity, a failure scenario, a fix, and VERIFIED or BELIEVED; end with a
merge verdict. Fold valid Critical/Major findings into the same push; ticket the rest rather than
starting another round. Verify its findings like any reviewer's.

If one section keeps getting flagged, stop patching it: replace an algorithm described in prose
with a contract (invariants and test cases), and prefer the rule that closes the whole class.

## Step 2 — Triage

For each finding, decide:

| Apply | Skip |
|-------|------|
| Bug or correctness issue | Style preference with no clear win, not in project standards |
| Security concern | False positive (code already correct) |
| Broken convention (per the repo's instructions) | Contradicts established project patterns |
| Clear improvement | Generated output (codegen, `dist/`, terraform-docs blocks), lockfiles, symlinked or vendored files — fix the source or regenerate instead |

If genuinely ambiguous, apply it. Spawn one Agent per file when there are many findings; give each
the finding verbatim, the file:line, and the thread IDs, and have it return VALID/SKIP plus a
one-or-two-sentence public rationale. Workers edit but do NOT commit.

**Stop and ask the user** before a fix that deletes code/resources or removes a public API,
changes a dependency or version constraint, or touches state-bearing config (migrations, remote
state, deployment or secrets config). If a suggestion would introduce a hardcoded secret, skip it
and tell the user.

## Step 3 — Validate

Run the project's own checks, preferring: `pre-commit run --all-files`; then its verify/lint/test
entry point (`package.json` scripts, `Taskfile.yml`/`Makefile`, `terraform fmt -check` +
`validate`, `ruff`/`pytest`, `go vet`/`go test`, `cargo clippy`/`test`); then whatever the repo's
instructions document. Run these before hand-verifying anything — the toolchain usually already
covers it. Fix failures; never bypass hooks with `--no-verify`. More than 5 iterations without
converging: stop and ask.

## Step 3b — Gate your own fix diff

Most round-2/3 findings are defects introduced while fixing round 1: reviewers go incremental, and
applying a suggestion feels smaller than authoring, so new content goes unchecked. Before
committing, re-read `git diff` as if reviewing someone else's PR:

1. **Every command you wrote or edited: run it, or stub it.** If it mutates anything (sets a
   secret, applies, deletes, overwrites, appends to a dotfile), stub the underlying CLI and check
   all four states of whatever it reads first:

   | state of the read | required behaviour |
   |---|---|
   | exits non-zero, prints nothing | no write; exits non-zero |
   | exits zero, prints nothing | no write; exits non-zero |
   | **prints a value, exits non-zero** | no write; exits non-zero |
   | prints a value, exits zero | write happens, value byte-exact, exit 0 |

   The third row is where the bugs are, and it is shell-dependent (fish's `set` does not gate an
   `&&` chain the way bash/zsh `v=$(cmd)` does). Prove the test catches it by running the old form
   against the new case. When stubbing a CLI, assert the stub actually won (`command -v <cli>`
   resolves inside the stub dir) before running anything — a minimal `PATH` and, for fish,
   `--no-config`; otherwise the real binary may run against live services.
2. **Audit every sibling** of the flagged command: when a finding says "this write is unguarded",
   grep the PR for every command that writes.
3. **Every reference you wrote must resolve** — anchors, paths, ticket IDs, function names. Use
   the linter, not a hand-rolled check.
4. **Never delete a guard to satisfy a "simplify" suggestion.** Error handling and validation are
   the exception to brevity; push back on that finding.
5. **A finding naming one instance of a class: fix every instance** (grep the repo).

## Step 4 — Commit and push

```bash
git add <changed files only — never git add -A>
git commit -m "fix: address review findings on PR #<PR>" -m "- <file:line> — what changed (reviewer)"
git push
```

One bullet per fix, attributing each to its reviewer. Verify the branch is not a base branch first.
Follow the repo's commit convention if it differs.

## Step 5 — Resolve and dismiss skipped findings

Don't leave skipped findings as unanswered threads. Per skipped inline comment, reply with the
rationale, then resolve the thread (use the thread node ID, not the comment databaseId):

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments/<COMMENT_ID>/replies -f body="Skipping: <rationale>."
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }' -F id=<THREAD_NODE_ID>
```

Also resolve any threads for fixed findings that the bot left open.

If a review is `CHANGES_REQUESTED` and the skips mean it won't be satisfied, dismiss it **only if
the reviewer is a bot** (e.g. `coderabbitai[bot]`):

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/reviews --jq '.[] | select(.state=="CHANGES_REQUESTED") | {id, user: .user.login}'
gh api --method PUT repos/{owner}/{repo}/pulls/<PR>/reviews/<REVIEW_ID>/dismissals \
  -f message="Addressed N, skipped M with reasons resolved on-thread. Dismissing to unblock." -f event=DISMISS
```

NEVER auto-dismiss a human reviewer's review: reply with the reasoning and let them re-review.

## Step 6 — Post the summary, then report and stop

```bash
gh pr comment <PR> --body "$(cat <<'EOF'
## Fix Summary

**Fixed**
- <file:line> — <what changed>

**Skipped** (resolved on-thread with reasoning)
- <finding> — <reason>
EOF
)"
```

If the repo's `.coderabbit.yaml` sets `reviews.auto_incremental_review: false`, a push triggers no
review: post one `@coderabbitai review` comment per batch (not per commit) and say you did.

**Do not poll for the next review** — it lands minutes later and sleep loops burn wall-clock and
misjudge the window. Report what you actually saw, timestamped: findings fixed, threads resolved,
review dismissed, CI result. Then say plainly that a re-review is expected and not yet seen. Never
call a PR "clear", "clean", "done", or "unblocked" on a review that may not have run;
`reviewDecision: REVIEW_REQUIRED` means a human approval is still needed. One `gh pr view` status
read is fine. For unattended convergence, suggest `/loop /fix-pr <PR>` and ask before assuming.

## Rules

- NEVER use `--no-verify`, push directly to a base branch, or auto-dismiss a human's review.
- NEVER apply a fix that contradicts established project patterns without flagging it.
- Repo-specific conventions live in the repo's instructions; they win over this skill.
