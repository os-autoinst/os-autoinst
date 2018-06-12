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
use Carp 'croak';

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;
    $self->{consoles}        = {};
    $self->{serial_failures} = {};

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
            my $marker = " ; echo $str-\$?-";
            testapi::type_string($marker);
            testapi::wait_serial($cmd . $marker, undef, 0, no_regex => 1);
            testapi::type_string("\n");
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

=head2 script_output

    script_output($script, [ $wait, type_command => ?, proceed_on_failure => ?])

Execute $script on the SUT and return the data written to STDOUT by
$script. See script_output in the testapi.

C<proceed_on_failure> - allows to proceed with validation when C<$script> is
failing (return non-zero exit code)

You may be able to avoid overriding this function by setting
$serial_term_prompt.

=cut
sub script_output {
    my ($self, $script, $wait, %args) = @_;
    my $marker = testapi::hashed_string("SO$script");
    # 80 is approximate quantity of chars typed during 'curl' approach
    # if script length is lower there is no point to proceed with more complex solution
    $args{type_command} //= length($script) < 80;
    my $script_path = "/tmp/script$marker.sh";
    # fail on error by default
    $args{proceed_on_failure} //= 0;

    # prevent use of network for offline installations
    if (testapi::get_var('OFFLINE_SUT')) {
        testapi::record_info('forced type_cmd', "Forced typing the command as we are offline");
        $args{type_command} = 1;
    }

    if (testapi::is_serial_terminal) {
        my $cat = "cat - > $script_path; echo $marker-\$?-";
        testapi::wait_serial($self->{serial_term_prompt}, undef, 0, no_regex => 1);
        testapi::type_string($cat . "\n");
        testapi::wait_serial("$cat", undef, 0, no_regex => 1);
        testapi::type_string($script);
        testapi::type_string("\n", terminate_with => 'EOT');
        testapi::wait_serial("$marker-0-");
    }
    elsif ($args{type_command}) {
        my $cat = "cat - > $script_path;\n";
        testapi::type_string($cat);
        testapi::type_string($script . "\n");
        testapi::send_key('ctrl-d');
    }
    else {
        open my $fh, ">", 'current_script' or croak("Could not open file. $!");
        print $fh $script;
        close $fh;
        testapi::assert_script_run("curl -f -v " . testapi::autoinst_url("/current_script") . " > $script_path");
        testapi::script_run "clear";
    }

    # Surround the actual script output with special markers so that we can
    # unambiguously separate the expected output from other content that we
    # might encounter on the serial device depending on how it is used in the
    # SUT
    my $shell_cmd = testapi::is_serial_terminal() ? 'bash -oe pipefail' : 'bash -eox pipefail';
    my $run_script = "echo $marker; $shell_cmd $script_path ; echo SCRIPT_FINISHED$marker-\$?-";
    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, undef, 0, no_regex => 1);
        testapi::type_string("$run_script\n");
        testapi::wait_serial($run_script, undef, 0, no_regex => 1);
    }
    else {
        testapi::type_string("($run_script) | tee /dev/$testapi::serialdev\n");
    }
    my $output = testapi::wait_serial("SCRIPT_FINISHED$marker-\\d+-", $wait, 0, record_output => 1)
      || croak "script timeout";

    if ($output !~ "SCRIPT_FINISHED$marker-0-") {
        croak "script failed with : $output" unless $args{proceed_on_failure};
    }

    # and the markers including internal exit catcher
    my $out = $output =~ /$marker(?<expected_output>.+)SCRIPT_FINISHED$marker-0-/s ? $+ : '';
    # trim whitespaces
    $out =~ s/^\s+|\s+$//g;
    return $out;
}

=head2 set_expected_serial_failures

    set_expected_serial_failures(%failures)

Define the patterns to look for in the serial console.
The patterns can be either I<hard> or I<soft>.

Example:
    set_expected_serial_failures(soft=>[qr/Pattern1/], hard=>[qr/Pattern2/]);

=cut
sub set_expected_serial_failures {
    my ($self, %failures) = @_;

    # To be sure that we only store soft and hard keys
    $self->{serial_failures}{soft} = $failures{soft} if $failures{soft};
    $self->{serial_failures}{hard} = $failures{hard} if $failures{hard};
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
