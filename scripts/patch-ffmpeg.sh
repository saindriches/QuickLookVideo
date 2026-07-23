#!/usr/bin/env bash
#
# patch-ffmpeg.sh — layer commits from a fork branch onto the ffmpeg submodule.
#
# The superproject pins the `ffmpeg` submodule at a base commit; the Xcode
# `ffmpeg` legacy target compiles whatever is in the ffmpeg/ working tree. This
# rewrites that tree by cherry-picking a selection of commits from a fork branch
# (e.g. saindriches/FFmpeg mmt-tlv) on top of the pinned base.
#
#   FFMPEG_FORK_URL       fork remote (default: saindriches/FFmpeg)
#   FFMPEG_PATCH_REF      branch/tag/sha to take (default: mmt-tlv)
#   FFMPEG_PATCH_BASE     range start; empty => merge-base(base, ref) = fork's own commits
#   FFMPEG_PATCH_COMMITS  explicit ordered commit list; overrides the range
#   FFMPEG_BASE_URL       https mirror for the pinned base (default: FFmpeg/FFmpeg)
#
set -euo pipefail
FFMPEG_FORK_URL="${FFMPEG_FORK_URL:-https://github.com/saindriches/FFmpeg.git}"
FFMPEG_PATCH_REF="${FFMPEG_PATCH_REF:-mmt-tlv}"
FFMPEG_PATCH_BASE="${FFMPEG_PATCH_BASE:-}"
FFMPEG_PATCH_COMMITS="${FFMPEG_PATCH_COMMITS:-}"
FFMPEG_BASE_URL="${FFMPEG_BASE_URL:-https://github.com/FFmpeg/FFmpeg.git}"

REPO_ROOT="$(git rev-parse --show-toplevel)"; cd "$REPO_ROOT"
BASE="$(git rev-parse "HEAD:ffmpeg")"
echo "==> ffmpeg pinned base: ${BASE}"

if [ ! -e ffmpeg/.git ]; then
  echo "==> initialising ffmpeg from ${FFMPEG_BASE_URL}"
  rm -rf ffmpeg && mkdir -p ffmpeg && git -C ffmpeg init -q
fi
cd ffmpeg
git cat-file -e "${BASE}^{commit}" 2>/dev/null || git fetch --no-tags "${FFMPEG_BASE_URL}" "${BASE}"
git checkout -q --detach "${BASE}"; git reset -q --hard "${BASE}"; git clean -qfdx
git remote remove fork 2>/dev/null || true
git remote add fork "${FFMPEG_FORK_URL}"
echo "==> fetching '${FFMPEG_PATCH_REF}' from ${FFMPEG_FORK_URL}"
git fetch --no-tags fork "${FFMPEG_PATCH_REF}"
PATCH_TIP="$(git rev-parse FETCH_HEAD)"

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-qlvideo-ci}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-ci@localhost}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

if [ -n "${FFMPEG_PATCH_COMMITS}" ]; then
  COMMITS="${FFMPEG_PATCH_COMMITS}"
else
  if [ -n "${FFMPEG_PATCH_BASE}" ]; then SINCE="$(git rev-parse "${FFMPEG_PATCH_BASE}")"
  else SINCE="$(git merge-base "${BASE}" "${PATCH_TIP}")"; echo "==> merge-base = ${SINCE}"; fi
  COMMITS="$(git rev-list --reverse --no-merges "${SINCE}..${PATCH_TIP}")"
fi
[ -z "${COMMITS//[[:space:]]/}" ] && { echo "==> nothing to apply"; exit 0; }

echo "==> applying $(echo "${COMMITS}" | wc -w | tr -d ' ') commit(s) onto $(git log --oneline -n1 "${BASE}")"
for c in ${COMMITS}; do echo "      + $(git log --oneline -n1 "$c")"; done
for c in ${COMMITS}; do
  git cherry-pick -x "$c" || { echo "!! conflict on $c"; git cherry-pick --abort || true; exit 1; }
done
echo "==> ffmpeg patched -> $(git rev-parse HEAD)"
