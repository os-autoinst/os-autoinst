#!BuildTag: os-autoinst_dev
FROM opensuse/leap:15.1

# Define environment variable
ENV NAME openQA test environment
ENV LANG en_US.UTF-8

RUN zypper ar -f -G 'http://download.opensuse.org/repositories/devel:/openQA:/Leap:/15.1/openSUSE_Leap_15.1' devel_openqa

RUN zypper in -y -C \
       aspell-en \
       aspell-spell \
       automake \
       curl \
       fftw3-devel \
       gcc \
       gcc-c++ \
       git \
       glibc-i18ndata \
       glibc-locale \
       gmp-devel \
       gzip \
       libexpat-devel \
       libsndfile-devel \
       libssh2-1 \
       libssh2-devel \
       libtheora-devel \
       libtool \
       libxml2-devel \
       make \
       opencv-devel \
       patch \
       perl \
       qemu \
       qemu-kvm \
       qemu-tools \
       ShellCheck \
       sudo \
       systemd-sysvinit \
       systemd libudev1 tack \
       tar \
       which \
       xorg-x11-fonts \
       'perl(Archive::Extract)' \
       'perl(Class::Accessor)' \
       'perl(Cpanel::JSON::XS)' \
       'perl(Crypt::DES)' \
       'perl(Devel::Cover)' \
       'perl(Devel::Cover::Report::Codecov)' \
       'perl(Exception::Class)' \
       'perl(File::Touch)' \
       'perl(IO::Scalar)' \
       'perl(IPC::Run)' \
       'perl(IPC::System::Simple)' \
       'perl(Mojo::IOLoop::ReadWriteProcess)' \
       'perl(Mojo::JSON)' \
       'perl(Net::DBus)' \
       'perl(Net::SSH2)' \
       'perl(Perl::Critic)' \
       'perl(Perl::Critic::Freenode)' \
       'perl(Pod::Coverage)' \
       'perl(Socket::MsgHdr)' \
       'perl(Test::Exception)' \
       'perl(Test::Fatal)' \
       'perl(Test::MockModule)' \
       'perl(Test::MockObject)' \
       'perl(Test::Mock::Time)' \
       'perl(Test::Output)' \
       'perl(Test::Pod)' \
       'perl(Test::Strict)' \
       'perl(Test::Warnings)' \
       'perl(Try::Tiny)' \
       'perl(XML::LibXML)' \
       'perl(XML::SemanticDiff)' \
  && true

VOLUME ["/sys/fs/cgroup", "/run"]

CMD ["/sbin/init"]

ENV OPENQA_DIR /opt/openqa
ENV NORMAL_USER squamata

RUN echo "$NORMAL_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
RUN useradd -r -d /home/$NORMAL_USER -m -g users --uid=1000 $NORMAL_USER
VOLUME [ "/opt/openqa" ]

# explicitly set user/group IDs

RUN mkdir -p /opt/testing_area
RUN chown -R $NORMAL_USER:users /opt/testing_area

ENTRYPOINT ["/bin/bash"]
WORKDIR $OPENQA_DIR
