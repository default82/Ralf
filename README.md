# Ralf

## Local Git hook support

This repository ships with a sample Git pre-commit hook under [`ci/pre-commit.sample`](ci/pre-commit.sample).
The hook keeps our shell tooling linted with [ShellCheck](https://www.shellcheck.net) and runs
secret detection so that credentials never make it into the history.

### Installing dependencies

Install the tooling that the hook relies on:

- [`shellcheck`](https://github.com/koalaman/shellcheck) – can be installed via your package manager (e.g. `brew install shellcheck`, `apt install shellcheck`).
- One of the secret scanners supported by the hook:
  - [`detect-secrets`](https://github.com/Yelp/detect-secrets) (preferred). Install with `pipx install detect-secrets` or `pip install detect-secrets`.
  - [`gitleaks`](https://github.com/gitleaks/gitleaks) as a fallback (`brew install gitleaks`, `apt install gitleaks`).

If you intend to use `detect-secrets`, initialise or update the baseline file (the hook looks
for `ci/detect-secrets.baseline` by default):

```bash
detect-secrets scan > ci/detect-secrets.baseline
```

Commit the baseline so everyone shares the same ignore list. Regenerate it whenever intentional
secrets (for example, test fixtures) change.

### Enabling the pre-commit hook locally

1. Copy the sample hook into your local Git hooks directory and make it executable:

   ```bash
   cp ci/pre-commit.sample .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```

   Alternatively, use a shared hooks directory so the hook stays up to date automatically:

   ```bash
   mkdir -p .githooks
   cp ci/pre-commit.sample .githooks/pre-commit
   git config core.hooksPath .githooks
   chmod +x .githooks/pre-commit
   ```

2. Stage some changes and run `git commit`. The hook will lint staged shell scripts and
   run the configured secret scanner. Fix any reported issues before committing.

To temporarily skip the hook you can pass `--no-verify` to `git commit`, but please use
this sparingly and follow up by addressing the reported problems.
