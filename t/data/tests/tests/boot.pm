# Copyright (C) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use base "basetest";
use strict;
use testapi;

sub run {
    # just assume the first screen has a timeout so we should make sure not to miss it
    assert_screen 'core', 15, no_wait => 1;
    # different variants of parameter selection
    assert_screen 'core', timeout => 60;
    assert_screen 'core', no_wait => 1;
    send_key 'ret';

    assert_screen 'on_prompt';

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
}

sub test_flags {
    return {important => 1};
}

1;

# vim: set sw=4 et:

