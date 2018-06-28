# Use an official SUSE runtime as a parent image
FROM registry.opensuse.org/devel/openqa/containers/openqa_dev

# Copy and run the install script
WORKDIR /opt/prepare
ADD . /opt/prepare

RUN sudo chown -R $NORMAL_USER:users /opt/prepare

# Where we will mount the travis (or local) build dir containing the os-autoinst git repo
VOLUME /opt/repo

ENTRYPOINT ["/opt/prepare/run.sh"]
