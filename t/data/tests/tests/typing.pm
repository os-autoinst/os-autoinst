# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run {
    assert_script_run 'cat /proc/cpuinfo';
    type_string "cat > text <<EOF\n";

    my $text = <<END;
==Description==
By default, a viewer/client uses TCP port 5900 to connect to a server (or 5800 for browser access), but can also be set to use any other port. Alternatively, a server can connect to a viewer in "listening mode" (by default on port 5500). One advantage of listening mode is that the server site does not have to configure its firewall/NAT to allow access on the specified ports; the burden is on the viewer, which is useful if the server site has no computer expertise, while the viewer user would be expected to be more knowledgeable.

Although RFB started as a relatively simple protocol, it has been enhanced with additional features (such as file transfers) and more sophisticated [[Data compression|compression]] and security techniques as it has developed. To maintain seamless cross-compatibility between the many different VNC client and server implementations, the clients and servers negotiate a connection using the best RFB version, and the most appropriate compression and security options that they can both support.

== History ==

RFB was originally developed at [[Olivetti Research Laboratory]] (ORL) as a remote display technology to be used by a simple [[thin client]] with [[Asynchronous Transfer Mode|ATM]] connectivity called a Videotile. In order to keep the device as simple as possible, RFB was developed and used in preference to any of the existing remote display technologies.

RFB found a second and more enduring use when VNC was developed. VNC was released as [[open source]] software and the RFB specification published on the web. Since then RFB has been a free protocol which anybody can use.

When ORL was closed in 2002 some of the key people behind VNC and RFB formed [[RealVNC]], Ltd., in order to continue development of VNC and to maintain the RFB protocol. The current RFB protocol is published on the RealVNC website.
END

    type_string $text;
    type_string "\nEOF\n";
    script_run "echo '924095f2cb4d622a8796de66a5e0a44a  text' > text.md5";
    assert_script_run 'md5sum -c text.md5';

    # TinyCore busybox sh acts as bash but does not provide it so we do here
    script_run 'alias bash=sh', 0;
    my $out = script_output('mount');
    die "mount does not show any mount points? output: $out" unless $out =~ /.*\/.*on/;
    die "^rootfs not found. output: $out" unless $out =~ qr{^rootfs};
    die "tmpfs on /dev/shm not found. output: $out" unless $out =~ qr{tmpfs on /dev/shm};

    enter_cmd 'echo do not wait_still_screen', max_interval => 50, wait_still_screen => 0;
    enter_cmd 'echo type string and wait for .2 seconds', wait_still_screen => .2;
    enter_cmd "echo test\necho wait\necho 1se", max_interval => 100, wait_screen_changes => 11, wait_still_screen => 1;
    enter_cmd 'echo test if wait_screen_change functions as expected',
      max_interval => 150,
      wait_screen_changes => 11,
      wait_still_screen => 1;
    enter_cmd 'echo wait_still_screen for .1 seconds', max_interval => 200, wait_still_screen => .1;
    enter_cmd "echo 'ignore \\r'\r";
}

sub test_flags {
    return {};
}

1;
