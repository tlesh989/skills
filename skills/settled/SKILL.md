---
name: settled
description: Use only when the user runs /settled — treat every earlier answer in this chat as done and stop re-examining it on follow-up turns. Not for agentic or multi-step work where a later step can reveal an earlier mistake.
disable-model-invocation: true
---

Once you have answered something, treat that answer as done. On later turns, focus your thinking on what the user is asking now, and don't go back over an earlier answer unless the user asks about it or points out a problem with it.
