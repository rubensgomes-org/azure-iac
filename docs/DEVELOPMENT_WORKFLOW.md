## Working on This Project

There are three primary workflows: making a modification, shipping a change and
cutting a release. All work occurs directly on the `main` branch. This
repository follows a trunk-based development model, with no feature branches or
pull requests.

The decision to use a single branch was made to keep the development and
maintenance of the project simple. This approach is appropriate because the
project was originally created by [Rubens Gomes](https://rubensgomes.com) to be
maintained by a single person.

### Starting New Work

Before starting new work, ensure that all required prerequisites are installed.

1. Sync the local `main` branch with the remote repository.

    ```bash
    # Always start from a current main.
    git switch main && git pull
    ```

2. Modify the project as needed.

3. Record the change under [Unreleased] in the `CHANGELOG.md` file accordingly.
   You must have an entry in the `CHANGELOG.md` prior to releasing.

4. Add, commit changes locally.

   ```bash
   # Nothing verifies or triggers a release automatically
   git add -A && git commit
   ```

5. Display the current version and run a preliminary release preflight check.

   ```bash
   # Nothing triggers a release automatically.  Follow Cutting a Release steps. 
   make version && make release-check
   ```

**Write the `CHANGELOG.md` entry as you go.** `make release-check` refuses to
cut a release on an empty `[Unreleased]`, so it has to happen eventually.

### Cutting a Release

Follow the steps below to cut a release.

1. Sync the local `main` branch with the remote repository.

    ```bash
    # Current main, and see what each bump level would produce.
    git switch main && git pull
    ```

2. Display the current version and run a release preflight only check reporting
   what each bump would produce.

    ```bash
    make version && make release-check
    ```

3. Bump the [Semantic Version](https://semver.org/) project version, roll
   changelog, commit, tag. Local only.

    ```bash
    # Bump. Applies version, rolls [Unreleased] CHANGELOG into a dated
    # section, commits, and creates the annotated tag.
    # All local — nothing is pushed.
    make release-patch             # or release-minor / release-major
    ```

   | Level   | Use for                                                       |
   |---------|---------------------------------------------------------------|
   | `patch` | docs and in-place tweaks no caller can observe                |
   | `minor` | new reusable workflows, composite actions, or optional inputs |
   | `major` | anything that breaks a consumer stub                          |

4. Push main, then the tag. The tag push fires `release.yml`, which validates
   the tag and publishes the GitHub Release.

    ```bash
    make release-push
    ```

5. Watch the run.

    ```bash
    gh run watch
    gh run list --workflow=release.yml
    ```

6. Re-run a release.

- ATTENTION: To re-run a release — a first attempt that failed, or one you want
  the SonarCloud gate on — dispatch the workflow **from the tag ref**, never
  from `main`. In the GitHub Actions UI the "Use workflow from" dropdown
  defaults to `main`; switch it to the `vX.Y.Z` tag.

  ```bash
  gh workflow run release.yml --ref vX.Y.Z
  ```

- Dispatching from a branch fails the workflow's first step with `Ref main
   does not match VERSION (vX.Y.Z)`. That gate is deliberate: the ref the run
  checks out is the ref that gets the GitHub Release, so it has to be the tag.

7. Final notes

- **Nothing leaves the machine until step 4**, which is the whole reason the
  bump and the push are separate. A mistyped level or a bad changelog roll is
  undone with `git tag -d vX.Y.Z && git reset --hard HEAD~1` — but only before
  step 4: a pushed tag is never moved.

- Run `make help` for the full list of targets, including `release-tag`, which
  tags the changelog's top version without bumping.

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
