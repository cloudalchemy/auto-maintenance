#!/usr/bin/env bash
# vim: ts=2 et

set -uo pipefail

git_mail="${GIT_MAIL:-cloudalchemybot@gmail.com}"
git_user="${GIT_USER:-cloudalchemybot}"

color_red='\e[31m'
color_green='\e[32m'
color_yellow='\e[33m'
color_none='\e[0m'

echo_red() {
  echo -e "${color_red}$*${color_none}"
}

echo_green() {
  echo -e "${color_green}$*${color_none}"
}

echo_yellow() {
  echo -e "${color_yellow}$*${color_none}"
}

github_token="${GH_TOKEN:-}"
if [[ -z "${github_token}" ]]; then
  echo_red 'GitHub token (GH_TOKEN) not set. Terminating.'
  exit 1
fi

github_api() {
  local url
  url="https://api.github.com/${1}"
  shift 1
  curl --retry 5 --silent --fail -u "${git_user}:${github_token}" "${url}" "$@"
}

# Only update git config if we're in bot mode.
if [[ "${git_user}" == 'cloudalchemybot' ]]; then
  git config --global user.email "${git_mail}"
  git config --global user.name "${git_user}"
fi

if [[ ! -d 'skeleton' ]]; then
  echo 'Cloning skeleton'
  git clone --quiet --depth 1 'https://github.com/cloudalchemy/skeleton.git' 'skeleton'
fi
LAST_COMMIT="$(cd skeleton && git rev-parse --short=8 HEAD)"
LAST_COMMIT_MSG="$(cd skeleton && git log -1 --pretty=%B | head -n1 | sed 's/"//g')"

PAYLOAD=$(cat <<EOF
{
  "title":"[REPO SYNC] ${LAST_COMMIT_MSG}",
  "base":"master",
  "head":"skeleton",
  "body":"One or more files which should be in sync across cloudalchemy repos were changed either here or in [cloudalchemy/skeleton](https://github.com/cloudalchemy/skeleton).\nThis PR propagates files from [cloudalchemy/skeleton](https://github.com/cloudalchemy/skeleton). If something was changed here, please first modify skeleton repository.\n\nCC: @paulfantom."
}
EOF
)

default_files='
  .gitignore
  .yamllint
  CONTRIBUTING.md
  test-requirements.txt
  .mergify.yml
'

add_missing_files='
  TROUBLESHOOTING.md
'

update_files='
  molecule/default/molecule.yml
  molecule/alternative/molecule.yml
  molecule/latest/molecule.yml
'

remove_files='
  .travis
  .travis.yml
  tox.ini
'

HERE=$(pwd)
github_api users/cloudalchemy/repos 2>/dev/null |
  jq -r '.[] | select(.archived == false and .fork == false and (.name | test("^ansible-.*$"))) | .name' |
  while read -r; do
  REPO="${REPLY}"
  if [[ "${REPO}" == 'ansible-pushprox' ]]; then
    echo_yellow "Skipping ${REPO}"
    continue
  fi
  echo_green "Analyzing ${REPO}"

  cd "${HERE}" || exit 1
  git clone --quiet --depth 1 "https://github.com/cloudalchemy/${REPO}.git" "${REPO}"
  cd "${REPO}" || exit 1
  git checkout -b "skeleton"

  # Replace files in target repo by ones from cloudalchemy/skeleton.
  cp -f ../skeleton/circleci-config.yml .circleci/config.yml
  cp -rf ../skeleton/.github/* .github/
  for f in ${default_files}; do
    cp -f "../skeleton/$f" "./$f"
  done
  # Sync parts of metadata file.
  sed -n '/---/,/author/p' meta/main.yml > meta.yml.tmp
  grep -E "(description|role_name):" meta/main.yml >> meta.yml.tmp || :
  sed -n '/license/,/galaxy_tags/p' ../skeleton/meta/main.yml | grep -v "galaxy_tags" >> meta.yml.tmp
  grep -A1000 galaxy_tags meta/main.yml >> meta.yml.tmp
  mv meta.yml.tmp meta/main.yml
  # Sync bottom part of README.md.
  grep -B1000 "## Local Testing" README.md | grep -v "## Local Testing" > README.md.tmp
  grep -A1000 "## Local Testing" ../skeleton/ROLE_README.md >> README.md.tmp
  sed -i "s/^- Ansible >=.*/$(grep '\- Ansible >=' ../skeleton/ROLE_README.md)/" README.md.tmp
  mv README.md.tmp README.md
  # Add if missing files.
  for f in ${add_missing_files}; do
    if [[ ! -f "$f" ]]; then
      cp "../skeleton/$f" "./$f"
    fi
  done
  # Update if exists files.
  for f in ${update_files}; do
    if [[ -f "$f" ]]; then
      cp "../skeleton/$f" "./$f"
    fi
  done
  # Cleanup old files.
  for f in ${remove_files}; do
    if [[ -a tox.ini ]]; then
       git rm -r "$f"
    fi
  done

  if [[ -n "$(git status --porcelain)" ]]; then
    git add .
    git commit -m ":robot: sync with cloudalchemy/skeleton (SHA: ${LAST_COMMIT}): ${LAST_COMMIT_MSG}"
    if git push "https://${git_user}:${github_token}@github.com/cloudalchemy/${REPO}" --set-upstream skeleton > /dev/null 2>&1; then
      pr_link=$(github_api "repos/cloudalchemy/${REPO}/pulls" -X POST -d "${PAYLOAD}" | jq -r '.html_url')
      echo_green "PR URL: ${pr_link}"
    else
      git push "https://${git_user}:${github_token}@github.com/cloudalchemy/${REPO}" --set-upstream skeleton --force > /dev/null 2>&1
    fi
  fi
done
