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
use Mojo::Base -strict;

use testapi ();
use Carp 'croak';

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;
    $self->{consoles}          = {};
    $self->{serial_failures}   = [];
    $self->{autoinst_failures} = [];

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
        'tty-console'       => 'ttyConsole',
        'ssh-serial'        => 'sshSerial',
        'ssh-xterm'         => 'sshXtermVt',
        'ssh-virtsh'        => 'sshVirtsh',
        'ssh-virtsh-serial' => 'sshVirtshSUT',
        'vnc-base'          => 'vnc_base',
        'local-Xvnc'        => 'localXvnc',
        'ssh-iucvconn'      => 'sshIucvconn',
        'virtio-terminal'   => 'virtio_terminal',
        'amt-sol'           => 'amtSol',
        'ipmi-sol'          => 'ipmiSol',
        'ipmi-xterm'        => 'sshXtermIPMI',
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

  script_run($cmd [, timeout => $timeout] [, output => $output] [,quiet => $quiet])

Deprecated mode

  script_run($program, [$timeout])

Run I<$cmd> (by assuming the console prompt and typing the command). After
that, echo hashed command to serial line and wait for it in order to detect
execution is finished. To avoid waiting, use I<$timeout> 0. The C<script_run>
command string must not be terminated with '&' otherwise an exception is
thrown.

Use C<output> to add a description or a comment of the $cmd.

Use C<quiet> to avoid recording serial_results.

<Returns> exit code received from I<$cmd>, or C<undef> in case of C<not> waiting for I<$cmd>
to return.

=cut

sub script_run {
    my ($self, $cmd) = splice(@_, 0, 2);
    my %args = testapi::compat_args(
        {
            timeout => $bmwqemu::default_timeout,
            output  => '',
            quiet   => undef
        }, ['timeout'], @_);

    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
    }
    testapi::type_string "$cmd";
    if ($args{timeout} > 0) {
        die "Terminator '&' found in script_run call. script_run can not check script success. Use 'background_script_run' instead."
          if $cmd =~ qr/(?<!\\)&$/;
        my $str    = testapi::hashed_string("SR" . $cmd . $args{timeout});
        my $marker = "; echo $str-\$?-" . ($args{output} ? "Comment: $args{output}" : '');
        if (testapi::is_serial_terminal) {
            testapi::type_string($marker);
            testapi::wait_serial($cmd . $marker, no_regex => 1, quiet => $args{quiet});
            testapi::type_string("\n");
        }
        else {
            testapi::type_string "$marker > /dev/$testapi::serialdev\n";
        }
        my $res = testapi::wait_serial(qr/$str-\d+-/, timeout => $args{timeout}, quiet => $args{quiet});
        return unless $res;
        return ($res =~ /$str-(\d+)-/)[0];
    }
    else {
        testapi::send_key 'ret';
        return;
    }
}

=head2 background_script_run

  background_script_run($cmd [, output => $output] [, quiet => $quiet])

Run I<$cmd> in background without waiting for it to finish. Remember to redirect output,
otherwise the PID marker may get corrupted.

Use C<output> to add a description or a comment of the $cmd.

Use C<quiet> to avoid recording serial_results.

<Returns> PID of the I<$cmd> process running in the background.

=cut

sub background_script_run {
    my ($self, $cmd, %args) = @_;

    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
    }

    $cmd = "( $cmd )";
    testapi::type_string $cmd;
    my $str    = testapi::hashed_string("SR" . $cmd);
    my $marker = "& echo $str-\$!-" . ($args{output} ? "Comment: $args{output}" : '');
    if (testapi::is_serial_terminal) {
        testapi::type_string($marker);
        testapi::wait_serial($cmd . $marker, no_regex => 1, quiet => $args{quiet});
        testapi::type_string("\n");
    }
    else {
        testapi::type_string "$marker > /dev/$testapi::serialdev\n";
    }
    my $res = testapi::wait_serial(qr/$str-\d+-/, quiet => $args{quiet});
    die 'PID marker not found' unless ($res =~ m/$str-(\d+)-/);
    return $1;
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

    script_output($script [, timeout => ?] [, type_command => ?] [, proceed_on_failure => ?] [, quiet => ?])

Deprecated mode

    script_output($script, [ $wait, type_command => ?, proceed_on_failure => ?])

Execute $script on the SUT and return the data written to STDOUT by
$script. See script_output in the testapi.

C<proceed_on_failure> - allows to proceed with validation when C<$script> is
failing (return non-zero exit code)

Use C<quiet> to avoid recording serial_results.

You may be able to avoid overriding this function by setting
$serial_term_prompt.

=cut
sub script_output {
    my ($self, $script) = splice(@_, 0, 2);
    my %args = testapi::compat_args(
        {
            timeout            => undef,
            proceed_on_failure => 0,       # fail on error by default
            quiet              => undef,
            # 80 is approximate quantity of chars typed during 'curl' approach
            # if script length is lower there is no point to proceed with more complex solution
            type_command => length($script) < 80,
        }, ['timeout'], @_);

    my $marker      = testapi::hashed_string("SO$script");
    my $script_path = "/tmp/script$marker.sh";

    # prevent use of network for offline installations
    if (testapi::get_var('OFFLINE_SUT')) {
        testapi::record_info('forced type_cmd', "Forced typing the command as we are offline");
        $args{type_command} = 1;
    }

    if (testapi::is_serial_terminal) {
        my $heretag = 'EOT_' . $marker;
        my $cat     = "cat > $script_path << '$heretag'; echo $marker-\$?-";
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
        bmwqemu::log_call("Content of $script_path :\n \"$cat\" \n");
        testapi::type_string($cat . "\n");
        testapi::wait_serial("$cat", no_regex => 1, quiet => $args{quiet});
        # Wait for input prompt of here tag before typing $script. This avoids
        # messy output, like duplicate output of $script. We do this in a second
        # wait_serial() call, to avoid issues during new line detection.
        testapi::wait_serial('> ', no_regex => 1, quiet => $args{quiet});
        testapi::type_string("$script\n$heretag\n");
        testapi::wait_serial("> $heretag", no_regex => 1, quiet => $args{quiet});
        testapi::wait_serial("$marker-0-", quiet => $args{quiet});
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
    my $shell_cmd  = testapi::is_serial_terminal() ? 'bash -oe pipefail' : 'bash -eox pipefail';
    my $run_script = "echo $marker; $shell_cmd $script_path ; echo SCRIPT_FINISHED$marker-\$?-";
    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
        testapi::type_string("$run_script\n");
        testapi::wait_serial($run_script, no_regex => 1, quiet => $args{quiet});
    }
    else {
        testapi::type_string("($run_script) | tee /dev/$testapi::serialdev\n");
    }
    my $output = testapi::wait_serial("SCRIPT_FINISHED$marker-\\d+-", timeout => $args{timeout}, record_output => 1, quiet => $args{quiet})
      || croak "script timeout: $script";

    if ($output !~ "SCRIPT_FINISHED$marker-0-") {
        my $log_message = 'script failed with : ' . $output;
        if ($args{proceed_on_failure}) {
            bmwqemu::log_call($log_message);
        }
        else {
            croak($log_message);
        }
    }

    # and the markers including internal exit catcher
    my $out = $output =~ /$marker(?<expected_output>.+)SCRIPT_FINISHED$marker-\d+-/s ? $+ : '';
    # trim whitespaces
    $out =~ s/^\s+|\s+$//g;
    return $out;
}

=head2 set_expected_serial_failures

    set_expected_serial_failures($failures)

Define the patterns to look for in the serial console.
Each pattern comes along with a type either I<hard> or I<soft> and a message,
for instance, to label the match with a bug/ticket

Example:
    set_expected_serial_failures([
        { type => 'soft', message => 'Message 1', pattern => qr/Pattern1/ },
        { type => 'soft', message => 'Message 2', pattern => qr/Pattern2/ },
        { type => 'hard', message => 'Message 3', pattern => qr/Pattern3/ },]
    );

=cut
sub set_expected_serial_failures {
    my ($self, $failures) = @_;

    $self->{serial_failures} = $failures;
}

=head2 set_expected_autoinst_failures

    set_expected_autoinst_failures($failures)

Define the patterns to look for in the os-autoinst-log.txt
Each pattern comes along with a type either I<hard> or I<soft> and a message,
for instance, to label the match with a bug/ticket

Example:
    set_expected_serial_failures([
        { type => 'soft', message => 'Message 1', pattern => qr/Pattern1/ },
        { type => 'soft', message => 'Message 2', pattern => qr/Pattern2/ },
        { type => 'hard', message => 'Message 3', pattern => qr/Pattern3/ },]
    );

=cut
sub set_expected_autoinst_failures {
    my ($self, $failures) = @_;

    $self->{autoinst_failures} = $failures;
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
