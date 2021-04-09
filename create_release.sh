#!/usr/bin/env bash
#
# Description: Generate the next release version

set -uo pipefail

if [[ -z "${PROJECT_USERNAME:-}" || -z "${PROJECT_REPONAME:-}" ]] ; then
  echo 'ERROR: Missing env PROJECT_USERNAME or PROJECT_REPONAME'
  exit 1
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo 'ERROR: Missing Github token ENV GH_TOKEN'
  exit 1
fi

project_url="https://github.com/${PROJECT_USERNAME}/${PROJECT_REPONAME}"
project_push_url="https://${GH_TOKEN}:@github.com/${PROJECT_USERNAME}/${PROJECT_REPONAME}.git"

if ! git config --global user.email "${GIT_MAIL:-cloudalchemybot@gmail.com}"; then
  echo 'ERROR: Unable to set git user.email'
  exit 1
fi

if ! git config --global user.name "${GIT_USER:-cloudalchemybot}"; then
  echo 'ERROR: Unable to set git user.email'
  exit 1
fi

latest_tag="$(git semver)"
if [[ -z "${latest_tag}" ]]; then
  echo "ERROR: Couldn't get latest tag from git semver, try 'pip install git-semver'" 2>&1
  exit 1
fi

# Use HEAD if CIRCLE_SHA1 is not set.
now="${CIRCLE_SHA1:-HEAD}"

new_tag='none'
git_log="$(git log --format=%B "${latest_tag}..${now}")"

case "${git_log}" in
  *"[major]"*|*"[breaking change]"* )    new_tag=$(git semver --next-major) ;;
  *"[minor]"*|*"[feat]"*|*"[feature]"* ) new_tag=$(git semver --next-minor) ;;
  *"[patch]"*|*"[fix]"*|*"[bugfix]"* )   new_tag=$(git semver --next-patch) ;;
esac

new_tag=$(git semver --next-major)

if [[ "${new_tag}" == 'none' ]]; then
  echo "Semver keyword not detected. No new release"
  exit 0
else
  echo "Bumping to ${new_tag}"
fi

run_git_chglog() {
  local outfile="$1"
  shift 1
  git-chglog \
    --config "${GIT_CHGLOG_CONFIG:-/etc/git-chglog/config.yml}" \
    --output "${outfile}" \
    --repository-url "${project_url}" "$@"
}

if ! run_git_chglog CHANGELOG.md --new-tag "${new_tag}"; then
  echo "ERROR: Generating CHANGELOG.md failed"
  exit 1
fi

if ! git add CHANGELOG.md; then
  echo "ERROR: Couldn't add CHANGELOG.md for commit"
  exit 1
fi

commit_message_file="$(mktemp)"

echo -e "Automatic release of ${new_tag}\n\n[ci skip]" > "${commit_message_file}"

run_git_chglog - "${new_tag}" | tail -n+4 >> "${commit_message_file}"

if ! git commit --file="${commit_message_file}"; then
  echo "ERROR: Couldn't commit CHANGELOG update"
  exit 1
fi

if ! git push "${project_push_url}"; then
  echo "ERROR: Failed to push commit"
  exit 1
fi

run_ghr() {
  ghr \
    -token "${GH_TOKEN}" \
    -username "${PROJECT_USERNAME}" \
    -repository "${PROJECT_REPONAME}" \
    -name "${new_tag}" \
    -body "$(< "${commit_message_file}")" \
    "${new_tag}"
}

if ! run_ghr; then
  echo "ERROR: Failed to push github release"
  exit 1
fi
