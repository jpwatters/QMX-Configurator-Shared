#!/bin/bash
# Upload the QMX-Configurator macOS port to GitHub:
#   https://github.com/jpwatters/QMX-Configurator-Shared
#
#   ./push-to-github.sh                       # commit message "Update QMX-Configurator macOS port"
#   ./push-to-github.sh "Describe the change" # your own commit message
#
# .zip files are never uploaded (QMX-Configurator-Win.zip,
# QMX-Configurator-macOS-port.zip, ...). Build output and Python environments
# (.venv, .venv-win, build/, dist/, __pycache__) are left out too.
# Uses your normal git sign-in for GitHub (gh auth login, or the macOS keychain).
set -euo pipefail
cd "$(dirname "$0")"

REPO_URL="${REPO_URL:-https://github.com/jpwatters/QMX-Configurator-Shared.git}"
BRANCH="main"
MSG="${1:-Update QMX-Configurator macOS port}"

command -v git >/dev/null || { echo "git not found. Install it with: xcode-select --install"; exit 1; }

# 1. Files git must never upload.
touch .gitignore
for pat in '*.zip' '.venv/' '.venv-win/' 'build/' 'dist/' '__pycache__/' '*.pyc' '*.spec' '.DS_Store'; do
  grep -qxF "$pat" .gitignore || echo "$pat" >> .gitignore
done

# 2. A git repository on branch main, pointing at GitHub.
if [ ! -d .git ]; then
  git init -q
  git symbolic-ref HEAD "refs/heads/$BRANCH"
  echo "Created a git repository here."
fi
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi
if ! git config user.name >/dev/null || ! git config user.email >/dev/null; then
  echo "git needs your name and email for the commit. Set them once with:"
  echo "  git config --global user.name  \"Your Name\""
  echo "  git config --global user.email \"you@example.com\""
  exit 1
fi

# 3. Stage everything except the ignored files, and drop any .zip tracked earlier.
git rm -r -q --cached --ignore-unmatch -- '*.zip' >/dev/null
git add -A
# Keep the launch scripts runnable after a clone.
for f in qmx-run-mac.command qmx-build-mac-app.sh push-to-github.sh; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && git update-index --chmod=+x -- "$f"
done
if git diff --cached --name-only --diff-filter=ACMR | grep -qi '\.zip$'; then
  echo "Refusing to continue: a .zip file is staged."; exit 1
fi
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -q -m "$MSG"
  echo "Committed: $MSG"
fi

# 4. If GitHub already has commits (e.g. a README made on the website), merge them first.
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git fetch -q origin "$BRANCH"
  if ! git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
    echo "GitHub has commits that aren't here yet - merging them."
    if ! git merge -q --no-edit --allow-unrelated-histories "origin/$BRANCH"; then
      git merge --abort || true
      echo "The merge had conflicts and was undone. Nothing was uploaded."
      echo "Resolve it by hand (git pull origin $BRANCH), then run this again."
      exit 1
    fi
  fi
fi

# 5. Last checks, then upload. git uploads every new commit, so a .zip added in
#    any commit not yet on GitHub would go up too, even if removed later.
if git ls-files | grep -qi '\.zip$'; then
  echo "Refusing to upload: a .zip file is tracked."; exit 1
fi
RANGE=HEAD
git rev-parse -q --verify "origin/$BRANCH" >/dev/null && RANGE="origin/$BRANCH..HEAD"
ZIPS=$(git log "$RANGE" --diff-filter=AM --name-only --pretty=format: | grep -i '\.zip$' | sort -u || true)
if [ -n "$ZIPS" ]; then
  echo "Refusing to upload: these .zip files are in commits not yet on GitHub:"
  echo "$ZIPS" | sed 's/^/  /'
  echo "Remove them from those commits first (or ask for help), then run this again."
  exit 1
fi
git push -u origin "$BRANCH"
echo
echo "Uploaded to ${REPO_URL%.git}"
git ls-files | sed 's/^/  /'
