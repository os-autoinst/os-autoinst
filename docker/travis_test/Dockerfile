# Use an official SUSE runtime as a parent image
FROM opensuse:42.3

# Copy and run the install script
WORKDIR /opt/prepare
ADD . /opt/prepare
RUN ./prepare.sh

# Where we will mount the travis (or local) build dir containing the os-autoinst git repo
VOLUME /opt/repo

ENTRYPOINT ["/opt/prepare/run.sh"]
