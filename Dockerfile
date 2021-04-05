FROM cimg/go:1.16 as build

ENV GHR_VERSION 0.13.0
ENV GIT_CHGLOG_VERSION 0.14.0

RUN \
  go install github.com/tcnksm/ghr@v${GHR_VERSION} && \
  go install github.com/git-chglog/git-chglog/cmd/git-chglog@v${GIT_CHGLOG_VERSION}

FROM cimg/python:3.9

RUN pip install git-semver

COPY --from=build /home/circleci/go/bin/ghr /usr/bin/ghr
COPY --from=build /home/circleci/go/bin/git-chglog /usr/bin/git-chglog

COPY create_release.sh /usr/bin/create_release
COPY git-chglog /etc/git-chglog
