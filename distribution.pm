# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package distribution;
use strict;
use warnings;

use testapi ();

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;
    $self->{consoles} = {};

=head2 serial_term_prompt

   wait_serial($serial_term_prompt);

A simple undecorated prompt for serial terminals. ANSI escape characters only
serve to create log noise in most tests which use the serial terminal, so
don't use them here. Also avoid using characters which have special meaning in
a regex. Note that our common prompt character '#' denotes a comment in a
regex with '/z' on the end, but if you are using /z you will need to wrap the
prompt in \Q and \E anyway otherwise the whitespace will be ignored.
=cut
    $self->{serial_term_prompt} = '# ';
    return $self;
}

sub init {
    # no cmds on default distri
}

sub add_console {
    my ($self, $testapi_console, $backend_console, $backend_args) = @_;

    my %class_names = (
        'tty-console'     => 'ttyConsole',
        'ssh-xterm'       => 'sshXtermVt',
        'ssh-virtsh'      => 'sshVirtsh',
        'vnc-base'        => 'vnc_base',
        'local-Xvnc'      => 'localXvnc',
        'ssh-iucvconn'    => 'sshIucvconn',
        'virtio-terminal' => 'virtio_terminal',
        'ipmi-sol'        => 'ipmiSol',
        'ipmi-xterm'      => 'sshXtermIPMI',
    );
    my $required_type = $class_names{$backend_console} || $backend_console;
    my $location      = "consoles/$required_type.pm";
    my $class         = "consoles::$required_type";

    require $location;

    my $ret = $class->new($testapi_console, $backend_args);
    # now the backend knows which console the testapi means with $testapi_console ("bootloader", "vnc", ...)
    $self->{consoles}->{$testapi_console} = $ret;
    return $ret;
}

sub x11_start_program {
    die "TODO: implement x11_start_program for your distri " . testapi::get_var('DISTRI');
}

sub ensure_installed {
    my ($self, @pkglist) = @_;

    if (testapi::check_var('DISTRI', 'debian')) {
        testapi::x11_start_program("su -c 'aptitude -y install @pkglist'", 4, {terminal => 1});
    }
    elsif (testapi::check_var('DISTRI', 'fedora')) {
        testapi::x11_start_program("su -c 'yum -y install @pkglist'", 4, {terminal => 1});
    }
    else {
        die "TODO: implement 'ensure_installed' for your distri " . testapi::get_var('DISTRI');
    }
    if ($testapi::password) { testapi::type_password; testapi::send_key("ret", 1); }
    wait_still_screen(7, 90);    # wait for install
}

sub become_root {
    my ($self) = @_;

    testapi::script_sudo("bash", 0);    # become root
    testapi::script_run('test $(id -u) -eq 0 && echo "imroot" > /dev/' . $testapi::serialdev, 0);
    testapi::wait_serial("imroot", 5) || die "Root prompt not there";
    testapi::script_run("cd /tmp");
}

=head2 script_run

script_run($program, [$wait_seconds])

Run I<$program> (by assuming the console prompt and typing the command). After that, echo
hashed command to serial line and wait for it in order to detect execution is finished.
To avoid waiting, use I<$wait_seconds> 0.

<Returns> exit code received from I<$program>, or 0 in case of C<not> waiting for I<$program>
to return.

=cut

sub script_run {
    # start console application
    my ($self, $cmd, $wait) = @_;
    $wait //= $bmwqemu::default_timeout;

    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, undef, 0, no_regex => 1);
    }
    testapi::type_string "$cmd";
    if ($wait > 0) {
        my $str = testapi::hashed_string("SR$cmd$wait");
        if (testapi::is_serial_terminal) {
            testapi::type_string " ; echo $str-\$?-\n";
        }
        else {
            testapi::type_string " ; echo $str-\$?- > /dev/$testapi::serialdev\n";
        }
        my $res = testapi::wait_serial(qr/$str-\d+-/, $wait);
        return unless $res;
        return ($res =~ /$str-(\d+)-/)[0];
    }
    else {
        testapi::send_key 'ret';
        return;
    }
}

=head2 script_sudo

script_sudo($program, $wait_seconds)

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds

=cut

sub script_sudo {
    my ($self, $prog, $wait) = @_;

    $wait //= 10;

    my $str;
    if ($wait > 0) {
        $str  = testapi::hashed_string("SS$prog$wait");
        $prog = "$prog; echo $str > /dev/$testapi::serialdev";
    }
    testapi::type_string "sudo $prog\n";
    if (testapi::check_screen "sudo-passwordprompt", 3) {
        testapi::type_password;
        testapi::send_key "ret";
    }
    if ($str) {
        return testapi::wait_serial($str, $wait);
    }
    return;
}

# override
sub activate_console {
    my ($self, $console) = @_;
}

# override
sub console_selected {
    my ($self, $console) = @_;
}

1;
# vim: set sw=4 et:
