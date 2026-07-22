#!/usr/bin/env bash
#
# patch-ffmpeg.sh — layer commits from a fork branch onto the ffmpeg submodule.
#
# General scheme
# --------------
# The QuickLookVideo superproject pins the `ffmpeg` submodule at a specific
# commit (the "base"). The Xcode `ffmpeg` legacy target compiles whatever source
# is sitting in the `ffmpeg/` working tree, so to ship a patched ffmpeg we simply
# rewrite that working tree BEFORE xcodebuild runs. This script does that by
# cherry-picking a selection of commits taken from a fork/branch (e.g. our fork's
# `mmt-tlv` branch) on top of the pinned base.
#
# Configure via environment variables:
#   FFMPEG_FORK_URL       git URL of the fork holding the patches        (REQUIRED)
#   FFMPEG_PATCH_REF      branch / tag / sha on the fork to take          (default: mmt-tlv)
#   FFMPEG_PATCH_BASE     "since" ref for the range; commits in
#                         FFMPEG_PATCH_BASE..FFMPEG_PATCH_REF are applied.
#                         Empty => use merge-base(pinned-base, patch ref),
#                         i.e. exactly the fork's own commits.
#   FFMPEG_PATCH_COMMITS  explicit, ordered, space/newline-separated commit
#                         list to cherry-pick; overrides the range logic.
#   FFMPEG_BASE_URL       https mirror to fetch the pinned base commit from
#                         (default: https://github.com/FFmpeg/FFmpeg.git — the
#                         .gitmodules git:// URL is frequently blocked on CI).
#
# Run from the repository root:   scripts/patch-ffmpeg.sh
#
set -euo pipefail

FFMPEG_FORK_URL="${FFMPEG_FORK_URL:-https://github.com/saindriches/FFmpeg.git}"
FFMPEG_PATCH_REF="${FFMPEG_PATCH_REF:-mmt-tlv}"
FFMPEG_PATCH_BASE="${FFMPEG_PATCH_BASE:-}"
FFMPEG_PATCH_COMMITS="${FFMPEG_PATCH_COMMITS:-}"
FFMPEG_BASE_URL="${FFMPEG_BASE_URL:-https://github.com/FFmpeg/FFmpeg.git}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Commit the superproject pins the ffmpeg submodule to.
BASE="$(git rev-parse "HEAD:ffmpeg")"
echo "==> ffmpeg pinned base: ${BASE}"

# Ensure ffmpeg/ is a populated git work tree, even if the git:// submodule
# fetch was skipped/blocked. We do a full (non-shallow) fetch on purpose so that
# merge-base and cherry-pick have the history they need.
if [ ! -e ffmpeg/.git ]; then
  echo "==> ffmpeg submodule not populated; initialising from ${FFMPEG_BASE_URL}"
  rm -rf ffmpeg && mkdir -p ffmpeg
  git -C ffmpeg init -q
fi

cd ffmpeg

if ! git cat-file -e "${BASE}^{commit}" 2>/dev/null; then
  echo "==> fetching base commit history"
  git fetch --no-tags "${FFMPEG_BASE_URL}" "${BASE}"
fi

git checkout -q --detach "${BASE}"
git reset  -q --hard   "${BASE}"
git clean  -qfdx

# Bring in the fork ref we want to take commits from.
git remote remove fork 2>/dev/null || true
git remote add fork "${FFMPEG_FORK_URL}"
echo "==> fetching '${FFMPEG_PATCH_REF}' from ${FFMPEG_FORK_URL}"
git fetch --no-tags fork "${FFMPEG_PATCH_REF}"
PATCH_TIP="$(git rev-parse FETCH_HEAD)"

# cherry-pick needs a committer identity.
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-qlvideo-ci}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-ci@localhost}"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"

# Decide which commits to apply.
if [ -n "${FFMPEG_PATCH_COMMITS}" ]; then
  COMMITS="${FFMPEG_PATCH_COMMITS}"
  echo "==> applying explicit commit list"
else
  if [ -n "${FFMPEG_PATCH_BASE}" ]; then
    SINCE="$(git rev-parse "${FFMPEG_PATCH_BASE}")"
  else
    SINCE="$(git merge-base "${BASE}" "${PATCH_TIP}")"
    echo "==> merge-base(base, ${FFMPEG_PATCH_REF}) = ${SINCE}"
  fi
  # --reverse: oldest first (cherry-pick order); --no-merges: skip merge commits.
  COMMITS="$(git rev-list --reverse --no-merges "${SINCE}..${PATCH_TIP}")"
fi

if [ -z "${COMMITS//[[:space:]]/}" ]; then
  echo "==> nothing to apply; ffmpeg left at pinned base"
  exit 0
fi

echo "==> base:   $(git log --oneline -n1 "${BASE}")"
echo "==> applying $(echo "${COMMITS}" | wc -w | tr -d ' ') commit(s):"
for c in ${COMMITS}; do
  echo "      + $(git log --oneline -n1 "${c}")"
done

for c in ${COMMITS}; do
  # -x records the original sha in the message for traceability.
  if ! git cherry-pick -x "${c}"; then
    echo "!! cherry-pick failed on ${c}" >&2
    git --no-pager diff --name-only --diff-filter=U || true
    git cherry-pick --abort || true
    echo "!! Resolve the conflict against the pinned base, or narrow" >&2
    echo "!! FFMPEG_PATCH_BASE / FFMPEG_PATCH_COMMITS, then retry." >&2
    exit 1
  fi
done

echo "==> ffmpeg patched -> $(git rev-parse HEAD)"
echo "==> patched HEAD log:"
git --no-pager log --oneline -n "$(( $(echo "${COMMITS}" | wc -w) + 1 ))"
