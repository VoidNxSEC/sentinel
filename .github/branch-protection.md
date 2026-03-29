# Branch Protection Rules

Apply these rules via GitHub UI: Settings → Branches → Add rule.

## `main`

| Setting | Value |
|---------|-------|
| Require a pull request before merging | ✅ |
| Required approvals | 1 |
| Dismiss stale reviews on push | ✅ |
| Require status checks to pass | ✅ |
| Required checks | `build-matrix`, `integration-tests`, `lint` |
| Require branches to be up to date | ✅ |
| Require signed commits | ✅ |
| Allow force pushes | ❌ |
| Allow deletions | ❌ |
| Include administrators | ✅ |

## `develop`

| Setting | Value |
|---------|-------|
| Require a pull request before merging | ✅ |
| Required approvals | 1 |
| Require status checks to pass | ✅ |
| Required checks | `build-matrix`, `quick-tests` |
| Allow squash merging only | ✅ |
| Allow force pushes | ❌ |

## Branch Naming Convention

```
main            ← protected, release-tagged
develop         ← integration target, PRs merge here first
feature/*       ← one branch per ROADMAP task (e.g. feature/m1-unified-compose)
release/v*      ← release candidates cut from develop
hotfix/*        ← emergency fixes branched from main
```

## Merge Strategy

- `feature/*` → `develop`: squash merge
- `release/v*` → `main`: merge commit (preserves release history)
- `hotfix/*` → `main` + `develop`: merge commit
