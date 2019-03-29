#!/bin/bash

set -euo pipefail

GIT_MAIL="cloudalchemybot@gmail.com"
GIT_USER="cloudalchemybot"
PAYLOAD='{"title":"Synchronize files from cloudalchemy/skeleton",
          "base":"master",
          "head":"skeleton",
          "body":"One or more files which should be in sync across cloudalchemy repos were changed either here or in [cloudalchemy/skeleton](https://github.com/cloudalchemy/skeleton).\nThis PR propagates files from [cloudalchemy/skeleton](https://github.com/cloudalchemy/skeleton). If something was changed here, please first modify skeleton repository.\n\nCC: @paulfantom."}'

if [ -z "${GITHUB_TOKEN}" ]; then
	echo -e "\e[31mGitHub token (GITHUB_TOKEN) not set. Terminating.\e[0m"
	exit 1
else
	export GITHUB_TOKEN=$GITHUB_TOKEN
fi

git config --global user.email "${GIT_MAIL}"
git config --global user.name "${GIT_USER}"

git clone "https://github.com/cloudalchemy/skeleton.git" "skeleton"

HERE=$(pwd)
curl https://api.github.com/users/cloudalchemy/repos 2>/dev/null | jq '.[].name' | grep '^"ansible' | sed 's/"//g' | while read -r; do
	REPO="$REPLY"
	echo -e "\e[32m Anylyzing $REPO\e[0m"

	cd "$HERE"
	git clone "https://github.com/cloudalchemy/$REPO.git" "$REPO"
	cd "$REPO"
	git checkout -b "skeleton"

	# Replace files in target repo by ones from cloudalchemy/skeleton
	cp -f ../skeleton/.github/* .github/
	cp -f ../skeleton/.yamllint ./
	cp -f ../skeleton/.gitignore ./
	cp -f ../skeleton/CONTRIBUTING.md ./
	cp -f ../skeleton/tox.ini ./
	cp -f ../skeleton/test-requirements.txt ./
	cp -f ../skeleton/.travis/releaser.sh ./.travis/releaser.sh
	if [ -n "$(git status --porcelain)" ]; then
		git add .
		git commit -m ':robot: synchronize files from cloudalchemy/skeleton'
		if git push "https://${GITHUB_TOKEN}:@github.com/cloudalchemy/${REPO}" --set-upstream skeleton; then
			curl -u "$GIT_USER:$GITHUB_TOKEN" -X POST -d "$PAYLOAD" "https://api.github.com/repos/cloudalchemy/${REPO}/pulls"
		fi
	fi
done
