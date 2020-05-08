# Container image that runs your code
FROM alpine:3.10

RUN apk update && apk add \
    perl \
    perl-dev \
    musl-dev \
    make \
    wget \
    perl-app-cpanminus \
  && true


RUN cpanm -n YAML::PP YAML XXX

# Copies your code file from your action repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# Code file to execute when the docker container starts up (`entrypoint.sh`)
ENTRYPOINT ["/entrypoint.sh"]
