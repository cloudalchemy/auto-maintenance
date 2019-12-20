#!/bin/bash

set -euo pipefail

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

git clone "https://github.com/cloudalchemy/skeleton.git" "skeleton"
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

HERE=$(pwd)
curl --retry 5 --silent -u "${GIT_USER}:${GITHUB_TOKEN}" https://api.github.com/users/cloudalchemy/repos 2>/dev/null | jq -r '.[] | select(.archived == false) | .name' | grep '^ansible' | while read -r; do
	REPO="$REPLY"
	echo -e "\e[32m Anylyzing $REPO\e[0m"

	cd "$HERE"
	git clone "https://github.com/cloudalchemy/$REPO.git" "$REPO"
	cd "$REPO"
	git checkout -b "skeleton"

	# Replace files in target repo by ones from cloudalchemy/skeleton
	cp -rf ../skeleton/.github/* .github/
	cp -f ../skeleton/.yamllint ./
	cp -f ../skeleton/.gitignore ./
	cp -f ../skeleton/CONTRIBUTING.md ./
	cp -f ../skeleton/tox.ini ./
	cp -f ../skeleton/test-requirements.txt ./
	cp -f ../skeleton/.travis/releaser.sh ./.travis/releaser.sh
	cp -f ../skeleton/.travis/test.sh ./.travis/test.sh
	cp -f ../skeleton/.travis.yml ./.travis.yml
	cp -f ../skeleton/.mergify.yml ./.mergify.yml
	mkdir -p molecule/default/tests
	cp -f ../skeleton/molecule/default/create.yml ./molecule/default/create.yml
	cp -f ../skeleton/molecule/default/destroy.yml ./molecule/default/destroy.yml
	cp -f ../skeleton/molecule/default/molecule.yml ./molecule/default/molecule.yml
	if [ -d "molecule/alternative" ]; then
		cp -f ../skeleton/molecule/alternative/molecule.yml ./molecule/alternative/molecule.yml
		if [ ! -f "molecule/alternative/prepare.yml" ]; then
			cp -f ../skeleton/molecule/alternative/prepare.yml ./molecule/alternative/prepare.yml
		fi
	fi
	if [ -d "molecule/latest" ]; then
		cp -f ../skeleton/molecule/latest/molecule.yml ./molecule/latest/molecule.yml
	fi
	# Sync parts of metadata file
	sed -n '/---/,/description/p' meta/main.yml > meta.yml.tmp
	grep "role_name:" meta/main.yml >> meta.yml.tmp || :
	sed -n '/license/,/galaxy_tags/p' ../skeleton/meta/main.yml | grep -v "galaxy_tags" >> meta.yml.tmp
	grep -A1000 galaxy_tags meta/main.yml >> meta.yml.tmp
	mv meta.yml.tmp meta/main.yml
	# Sync bottom part of README.md
	grep -B1000 "## Local Testing" README.md | grep -v "## Local Testing" > README.md.tmp
	grep -A1000 "## Local Testing" ../skeleton/ROLE_README.md >> README.md.tmp
	sed -i "s/^- Ansible >=.*/$(grep '\- Ansible >=' ../skeleton/ROLE_README.md)/" README.md.tmp
	sed -i '/IRC/d' README.md.tmp
	mv README.md.tmp README.md

	if [ -n "$(git status --porcelain)" ]; then
		git add .
		git commit -m ":robot: sync with cloudalchemy/skeleton (SHA: ${LAST_COMMIT}): $LAST_COMMIT_MSG"
		if git push "https://${GITHUB_TOKEN}:@github.com/cloudalchemy/${REPO}" --set-upstream skeleton; then
			curl -u "$GIT_USER:$GITHUB_TOKEN" -X POST -d "$PAYLOAD" "https://api.github.com/repos/cloudalchemy/${REPO}/pulls"
		else
			git push "https://${GITHUB_TOKEN}:@github.com/cloudalchemy/${REPO}" --set-upstream skeleton --force
		fi
	fi
done
