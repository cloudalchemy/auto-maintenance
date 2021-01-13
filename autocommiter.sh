#!/bin/bash

set -euo pipefail

GIT_MAIL="cloudalchemybot@gmail.com"
GIT_USER="cloudalchemybot"

if [[ $# -ne 2 ]]; then
    echo "usage $(basename $0) <source repo> <destination repo>"
    exit 1
fi

SRC="$1"
DST="$2"

if [ -z "${GH_TOKEN}" ]; then
    echo -e "\e[31mGitHub token (GH_TOKEN) not set. Terminating.\e[0m"
    exit 128
fi

if [ -z "${SRC}" ]; then
    echo -e "\e[31mNo source repository set. Terminating.\e[0m"
    exit 128
fi

if [ -z "${DST}" ]; then
    echo -e "\e[31mNo destination repository set. Terminating.\e[0m"
    exit 128
fi

# Get new version
VERSION="$(curl --retry 5 --silent -u "${GIT_USER}:${GH_TOKEN}" "https://api.github.com/repos/${SRC}/releases/latest" | jq '.tag_name' | tr -d '"v')"
echo -e "\e[32mNew ${SRC} version is: ${VERSION}\e[0m"

# Download destination repository
git clone "https://github.com/${DST}" "${DST}"
if grep "_version: ${VERSION}" "${DST}/defaults/main.yml"; then
    echo -e "\e[32mNewest version is used.\e[0m"
    exit 0
fi
sed -i "s/_version:.*$/_version: ${VERSION}/" "${DST}/defaults/main.yml"
sed -i -r "s/_version.*[0-9]+\.[0-9]+\.[0-9]+/_version\` | ${VERSION}/" "${DST}/README.md"

# Push new version
cd "${DST}"
git config user.email "${GIT_MAIL}"
git config user.name "${GIT_USER}"
git checkout -b autoupdate
git add "defaults/main.yml" "README.md"
git commit -m ':tada: automated upstream release update'
echo -e "\e[32mPushing to autoupdate branch in ${DST}\e[0m"
if ! git push "https://${GH_TOKEN}:@github.com/${DST}" --set-upstream autoupdate; then
    echo -e "\e[33mBranch is already on remote.\e[0m"
    exit 129
fi

PAYLOAD="{\"title\": \"New ${SRC} upstream release!\",
          \"base\": \"master\",
          \"head\": \"autoupdate\",
          \"body\": \"Devs at [${SRC}](https://github.com/${SRC}) released new software version - **${VERSION}**! This PR updates code to bring new version into repository.\n\nThis is an automated PR, if you don't want to receive those, please contact @paulfantom.\n\n## Commit Message\ncreate [patch] release\"}"

curl --retry 3 --silent -u "${GIT_USER}:${GH_TOKEN}" -X POST -d "${PAYLOAD}" "https://api.github.com/repos/${DST}/pulls"
echo -e "\e[32mPull Request with new version is ready\e[0m"
