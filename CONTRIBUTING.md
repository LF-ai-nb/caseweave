# Contributing

Thanks for improving CaseWeave.

## Local workflow

```bash
moon check
moon build
moon test
moon run cmd/main
```

Before opening a pull request:

- keep the core library free of runtime IO
- add tests for public behavior changes
- update `README.md` or `docs/` when behavior or usage changes
- update `CHANGELOG.md` for user-visible changes
- record any new third-party dependency in `NOTICE.md`

## Commit style

Use short, scoped commit messages such as:

- `feat: add constrained coverage audit`
- `test: cover csv escaping`
- `docs: explain constraint pruning`
- `ci: validate moon build and tests`
