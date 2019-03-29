#!/bin/bash

set -eo pipefail

GIT_MAIL="cloudalchemybot@gmail.com"
GIT_USER="cloudalchemybot"
PAYLOAD='{"title":"Synchronize Makefile.common",
          "base":"master",
          "head":"makefile_common",
          "body":"CC: @SuperQ"}'

if [ -z "${GITHUB_TOKEN}" ]; then
	echo -e "\e[31mGitHub token (GITHUB_TOKEN) not set. Terminating.\e[0m"
	exit 1
else
	export GITHUB_TOKEN=$GITHUB_TOKEN
fi

git config --global user.email "${GIT_MAIL}"
git config --global user.name "${GIT_USER}"

CHECKSUM=$(curl https://raw.githubusercontent.com/prometheus/prometheus/master/Makefile.common 2>/dev/null | sha256sum | cut -d' ' -f1)

HERE=$(pwd)
curl https://api.github.com/users/prometheus/repos 2>/dev/null | jq '.[].name' | sed 's/"//g' | while read -r; do
	REPO="$REPLY"
	echo -e "\e[32m Anylyzing $REPO\e[0m"
	if [ "$(curl "https://raw.githubusercontent.com/prometheus/$REPO/master/Makefile.common" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$CHECKSUM" ]; then
		continue
	fi
	cd "$HERE"
	git clone "https://github.com/prometheus/$REPO.git" "$REPO"
	cd "$REPO"
	git checkout -b "makefile_common"
	rm Makefile.common
	curl https://raw.githubusercontent.com/prometheus/prometheus/master/Makefile.common
	git add Makefile.common
	git commit -m ':robot: synchronize Makefile.common from prometheus/prometheus'
	if git push "https://${GITHUB_TOKEN}:@github.com/prometheus/${REPO}" --set-upstream makefile_common; then
		curl -u "$GIT_USER:$GITHUB_TOKEN" -X POST -d "$PAYLOAD" "https://api.github.com/repos/prometheus/${REPO}/pulls"
	fi
done
