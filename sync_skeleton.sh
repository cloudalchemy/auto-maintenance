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
LAST_COMMIT="$(cd skeleton && git rev-parse --short=8 HEAD)"

HERE=$(pwd)
curl --retry 5 --silent -u "${GIT_USER}:${GITHUB_TOKEN}" https://api.github.com/users/cloudalchemy/repos 2>/dev/null | jq '.[].name' | grep '^"ansible' | sed 's/"//g' | while read -r; do
	REPO="$REPLY"
	echo -e "\e[32m Anylyzing $REPO\e[0m"

	# ansible-ebpf_exporter is archived
	if [ "$REPO" == "ansible-ebpf_exporter" ]; then
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
	cp -f ../skeleton/.travis.yml ./.travis.yml
	mkdir -p molecule/default
	cp -f ../skeleton/molecule/default/create.yml ./molecule/default/create.yml
	cp -f ../skeleton/molecule/default/destroy.yml ./molecule/default/destroy.yml
#	cp -f ../skeleton/molecule/default/molecule.yml ./molecule/default/molecule.yml # TODO(paulfantom): enable after all projects are able to run on fedora 30
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
	mv README.md.tmp README.md

	if [ -n "$(git status --porcelain)" ]; then
		git add .
		git commit -m ":robot: synchronize with last commit in cloudalchemy/skeleton (SHA: ${LAST_COMMIT})"
		if git push "https://${GITHUB_TOKEN}:@github.com/cloudalchemy/${REPO}" --set-upstream skeleton; then
			curl -u "$GIT_USER:$GITHUB_TOKEN" -X POST -d "$PAYLOAD" "https://api.github.com/repos/cloudalchemy/${REPO}/pulls"
		fi
	fi
done
