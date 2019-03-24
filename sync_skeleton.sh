#!/bin/bash

set -eo pipefail

GIT_MAIL="cloudalchemybot@gmail.com"
GIT_USER="cloudalchemybot"

if [ -z "${GITHUB_TOKEN}" ]; then
	echo -e "\e[31mGitHub token (GITHUB_TOKEN) not set. Terminating.\e[0m"
	exit 1
else
	export GITHUB_TOKEN=$GITHUB_TOKEN
fi

git config --global user.email "${GIT_MAIL}"
git config --global user.name "${GIT_USER}"
if ! command -v hub 1>/dev/null 2>&1; then
	# Download hub
	HUB_VERSION="2.10.0"
	curl -sOL "https://github.com/github/hub/releases/download/v${HUB_VERSION}/hub-linux-amd64-${HUB_VERSION}.tgz"
	tar -xf "hub-linux-amd64-${HUB_VERSION}.tgz"
	cp "hub-linux-amd64-${HUB_VERSION}/bin/hub" ./
	chmod +x hub
	PATH="${PATH}:$(pwd)"
fi

git clone "https://github.com/cloudalchemy/skeleton.git" "skeleton"

HERE=$(pwd)
curl https://api.github.com/users/cloudalchemy/repos 2>/dev/null | jq '.[].name' | grep '^"ansible' | sed 's/"//g' | while read -r; do
	REPO="$REPLY"
	echo -e "\e[32m Anylyzing $REPO\e[0m"
	# Exclude coredns as it is not finished yet
	if [ "$REPO" == "ansible-coredns" ]; then
		continue
	fi

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
			hub pull-request -h skeleton -F- <<<"Synchronize files from cloudalchemy/skeleton.

One of files which should be in sync across all cloudalchemy repos was changed either here or in cloudalchemy/skeleton. 
This PR propagates files from cloudalchemy/skeleton. If something was changed here, please first modify repo skeleton.

CC: @paulfantom."

		fi
	fi
done
