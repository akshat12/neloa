# Repository workflow

- Work directly on `main` unless the user explicitly requests another branch.
- Once a requested change is complete and relevant checks pass, commit it at a sensible checkpoint and push it to `origin/main` before handing the work back to the user.
- Include all completed repository changes from the current task in that push, while preserving unrelated user changes.
- Never force-push, rewrite published history, or push known failing or incomplete work. If a normal push is rejected or unavailable, keep the commits locally and report the blocker clearly.
