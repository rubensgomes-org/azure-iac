## Working Rules

- **This file is read-only.** Propose changes and wait for approval; never edit
  it as a side effect of other work. Durable facts go to `docs/`, dated changes
  to `CHANGELOG.md`.
- **Write only what was asked.** No adjacent sections, anticipated follow-ups,
  or unrequested rationale in documentation. Match the length of the answer
  already given in the terminal; offer a fuller version rather than writing it.
- Plan before implementing significant changes. And always store your plans
  plans in `misc/tasks` folder.
- **The user runs all `terraform` commands.** Never `terraform apply` or
  `terraform destroy` from an agent session.
- **`make fmt` and `make validate` before committing** — no workflow verifies
  `main` automatically, so this is the only gate.
- Match the style of `terraform/bootstrap-backend/` for new module code — block
  comments explaining "why", not just "what".
- **Trunk-based**: `main` is the only branch. No feature branches, no PRs. Do
  not create one unless asked.
