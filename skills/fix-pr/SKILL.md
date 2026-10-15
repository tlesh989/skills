---
name: fix-pr
description: Use when a PR has review comments to address — fetches CodeRabbit/human reviewer feedback for a PR, fixes valid issues, resolves skipped threads with reasons, and pushes. Runs local different-model reviews to spare the hosted reviewer's rate-limited allowance
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

## Step 1b — Spend hosted review on purpose; review locally by default

Hosted review bots (CodeRabbit and the like) are **rate-limited**: a plan grants a few reviews per
hour, and a re-review of a large PR spends one. A local review by a subagent on a different model
costs nothing against that budget and, unlike an incremental bot pass, can be pointed at the whole
PR. So the bot gets the review it runs when the PR opens, and local reviews carry the fix rounds.

**How to run a local review:** spawn one read-only `general-purpose` Agent with a `model` different
from this session's. No edits, commits, or GitHub posts. Give it the scope (below) and ask for one
ranked pass, most severe first. Each finding needs lines, severity (Critical/Major/Minor), a failure
scenario, a fix, and VERIFIED (reproduced) or BELIEVED. End with a merge verdict. Verify its
findings like any reviewer's.

| When | Scope of the local review |
|---|---|
| No full review of this PR exists yet (bot or local) | The whole PR: `git diff <base>...HEAD` |
| Round 3 or later (`git log --oneline <base>..HEAD \| grep -c 'address .*review'`), or a section flagged again | The whole PR |
| Every other fix round, before pushing | This round's fix diff: `git diff @{upstream}` |

Fold valid Critical/Major findings into the same push. Fix a Minor when it is a real defect;
otherwise ticket it rather than start another round.

**Folded-in fixes are new code, so review them too before pushing.** After each review pass,
stage what it saw (`git add <files>`, including any new files); plain `git diff` then shows
only the edits made since, and that is the next pass's scope. Repeat while a pass finds a Critical/Major. When a pass finds only
Minors, fix the real defects, ticket the rest, and stop. Those last edits get no review pass,
only the Step 3b self-gate, so keep them small. If the same code produces Critical/Majors twice,
use the contract rule at the end of this step instead of another pass.

These follow-up passes belong to the round they fix. They do not count as a new round for the
round-3 trigger or the stop rule, and a round re-requests the hosted bot at most once, after its
final push.

**Re-request the hosted bot only when** a fix round changed logic substantially (a new branch, a
reordered sequence, a rewritten algorithm), or a local review found a Critical/Major. Otherwise do
not: the local fix-diff review already covered the round. Say which way you decided and why.

When that trigger fires, **try the CodeRabbit CLI first** (see `coderabbit-cli.md`, including
when to skip it), and post `@coderabbitai full review` only if the CLI is unavailable, out of reviews, or
failed. The CLI stands in for that one re-request per round, nothing more. It does not replace the
opening hosted review, it does not satisfy a required `CodeRabbit` status check, and the cheap
subagent passes still carry the fold-in follow-ups.

How to run the CLI review, and when to skip it: **read `coderabbit-cli.md`, next to this
`SKILL.md` in the skill's base directory**, before the first CLI call. It covers the checks, flags, scope, output, and the untrusted-text rule.

**Stop requesting reviews when both hold:**

1. The last round's findings were all Minor **and** all inside code written during fix rounds,
   not the original design.
2. Every commit has had at least one full review, bot or local. A one-line fix a local fix-diff
   review covered counts.

Severity alone is not the signal. A Minor finding can still be a real bug, so fix it. What matters
is whether another round would look at anything new. Equally, never stop because a round count was
reached: a fix round is new code and can be wrong in new ways.

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

When Step 1b says to re-request the hosted bot, put the request in this summary comment. One per
batch, never per commit. Say in the report whether you requested one and why. If a CodeRabbit CLI
review stood in for it, list that review's findings and their outcomes under a `**CodeRabbit CLI
(--deep)**` heading, since they never appear on the PR.

⚠️ **CodeRabbit with `reviews.auto_review.auto_incremental_review: false`:** a push gets no review,
yet CodeRabbit still sets its status check to **success**, so a green `CodeRabbit` check does not
mean the commit was reviewed. `@coderabbitai review` then fails with "does not re-review already
reviewed commits" (the skipped push appears to count as handled). Use `@coderabbitai full review`,
which runs in this mode and costs one review from the allowance.
`@coderabbitai rate limit` shows the remaining allowance without spending any.

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
