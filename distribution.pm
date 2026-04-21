# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package distribution;
use Mojo::Base -strict, -signatures;

use testapi ();
use log 'fctwarn';
use Carp 'croak';

sub new ($class, @) {
    my $self = bless {}, $class;
    $self->{consoles} = {};
    $self->{serial_failures} = [];
    $self->{autoinst_failures} = [];
    $self->{_serial_marker_level} = {};

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

# no cmds on default distri
sub init ($self) { }

sub add_console ($self, $testapi_console, $backend_console, $backend_args = undef) {
    my %class_names = (
        'tty-console' => 'ttyConsole',
        'ssh-serial' => 'sshSerial',
        'ssh-xterm' => 'sshXtermVt',
        'ssh-virtsh' => 'sshVirtsh',
        'ssh-virtsh-serial' => 'sshVirtshSUT',
        'vnc-base' => 'vnc_base',
        'local-Xvnc' => 'localXvnc',
        'ssh-iucvconn' => 'sshIucvconn',
        'virtio-terminal' => 'virtio_terminal',
        'ipmi-sol' => 'ipmiSol',
        'ipmi-xterm' => 'sshXtermIPMI',
        'video-stream' => 'video_stream',
    );
    my $required_type = $class_names{$backend_console} || $backend_console;
    my $location = "consoles/$required_type.pm";
    my $class = "consoles::$required_type";

    require $location;

    my $ret = $class->new($testapi_console, $backend_args);
    # now the backend knows which console the testapi means with $testapi_console ("bootloader", "vnc", ...)
    $self->{consoles}->{$testapi_console} = $ret;
    return $ret;
}

sub x11_start_program (@) {
    die 'TODO: implement x11_start_program for your distri ' . testapi::get_var('DISTRI', '');
}

sub ensure_installed ($self, @pkglist) {
    if (testapi::check_var('DISTRI', 'debian')) {
        testapi::x11_start_program("su -c 'aptitude -y install @pkglist'", 4, {terminal => 1});
    }
    elsif (testapi::check_var('DISTRI', 'fedora')) {
        testapi::x11_start_program("su -c 'yum -y install @pkglist'", 4, {terminal => 1});
    }
    else {
        die "TODO: implement 'ensure_installed' for your distri " . testapi::get_var('DISTRI', '');
    }
    if ($testapi::password) { testapi::type_password; testapi::send_key('ret'); }
    testapi::wait_still_screen(7, 90);    # wait for install
}

sub become_root ($self) {
    testapi::script_sudo('bash', 0);    # become root
    testapi::enter_cmd('test $(id -u) -eq 0 && echo "imroot" > /dev/' . $testapi::serialdev, 0);
    testapi::wait_serial('imroot') || die 'Root prompt not there';
    testapi::enter_cmd('cd /tmp');
}

=head 2 disable_key_repeat

  disable_key_repeat()

Disable the key repetition in a Linux tty. Needs to be called in each newly
activated tty, e.g. in C<activate_console> in the distribution implementation.

kbdrate can control the key repeat rate and delay but only if Linux controls
the input stream. For this suggested way is to use "virtio-keyboard" which is
enabled in os-autoinst by default. Alternatively set the Linux kernel parameter
"atkbd.softrepeat=1".

=cut

sub disable_key_repeat ($self) {
    testapi::enter_cmd('kbdrate -s -d99999');
}

sub _handle_cmd_typing_error ($cmd, $args) { ($args->{check_typing_cmd} // 1 ? \&croak : \&fctwarn)->("typing command '$cmd' timed out") }

=head2 script_run

  script_run($cmd [, timeout => $timeout] [, output => $output] [,quiet => $quiet] [,max_interval => $max_interval])

Deprecated mode

  script_run($program, [$timeout])

Run I<$cmd> (by assuming the console prompt and typing the command). After
that, echo hashed command to serial line and wait for it in order to detect
execution is finished. To avoid waiting, use I<$timeout> 0. The C<script_run>
command string must not be terminated with '&' otherwise an exception is
thrown.

Use C<output> to add a description or a comment of the $cmd.

Use C<quiet> to avoid recording serial_results.

Use C<max_interval> (1-250) to control the typing speed. Lower values mean slower
typing.

<Returns> exit code received from I<$cmd>, or C<undef> in case of C<not> waiting for I<$cmd>
to return.

=cut

sub script_run ($self, $cmd, @args) {
    my %args = testapi::compat_args(
        {
            timeout => $bmwqemu::default_timeout,
            check_typing_cmd => 1,
            output => '',
            quiet => undef,
            max_interval => testapi::DEFAULT_MAX_INTERVAL
        }, ['timeout'], @args);

    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
    }

    if ($args{timeout} > 0) {
        die "Terminator '&' found in script_run call. script_run can not check script success. Use 'background_script_run' instead."
          if $cmd =~ qr/(?<!\\)&$/;

        my $level = $self->_detect_serial_marker_capability();
        my ($str, $wait_pattern);
        if ($level == 3) {
            testapi::query_isotovideo('backend_clear_serial_buffer', {});
            testapi::type_string "$cmd\n", max_interval => $args{max_interval};
            my $res = testapi::wait_serial(qr/OA:DONE-[0-9a-f]{4}-(\d+)-/, timeout => $args{timeout}, quiet => $args{quiet}, record_command => $cmd, internal_marker => 1);
            return unless $res;
            return ($res =~ /OA:DONE-[0-9a-f]{4}-(\d+)-/)[0];
        }
        $str = testapi::hashed_string('SR' . $cmd . $args{timeout});
        $wait_pattern = qr/$str-(\d+)-/;
        if ($level == 2) {
            testapi::type_string "export __OA_MARK=$str; $cmd\n", max_interval => $args{max_interval};
        }
        else {
            my $marker = "; echo $str-\$?-" . ($args{output} ? "Comment: $args{output}" : '');
            if (testapi::is_serial_terminal) {
                testapi::type_string "$cmd", max_interval => $args{max_interval};
                testapi::type_string $marker, max_interval => $args{max_interval};
                testapi::wait_serial($cmd . $marker, no_regex => 1, quiet => $args{quiet}, buffer_size => (length $cmd) + 128, internal_marker => 1)
                  or _handle_cmd_typing_error($cmd, \%args);
                testapi::type_string "\n", max_interval => $args{max_interval};
            }
            else {
                testapi::type_string "$cmd", max_interval => $args{max_interval};
                testapi::type_string "$marker > /dev/$testapi::serialdev\n", max_interval => $args{max_interval};
            }
        }
        my $res = testapi::wait_serial($wait_pattern, timeout => $args{timeout}, quiet => $args{quiet}, record_command => $cmd, internal_marker => 1);
        return unless $res;
        return ($res =~ $wait_pattern)[0];
    }
    else {
        testapi::type_string "$cmd", max_interval => $args{max_interval};
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

sub background_script_run ($self, $cmd, %args) {
    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
    }

    $cmd = "( $cmd )";
    testapi::type_string $cmd;
    my $str = testapi::hashed_string('SR' . $cmd);
    my $marker = "& echo $str-\$!-" . ($args{output} ? "Comment: $args{output}" : '');
    if (testapi::is_serial_terminal) {
        testapi::type_string $marker;
        testapi::wait_serial($cmd . $marker, no_regex => 1, quiet => $args{quiet}, internal_marker => 1) or _handle_cmd_typing_error($cmd, \%args);
        testapi::type_string "\n";
    }
    else {
        testapi::type_string "$marker > /dev/$testapi::serialdev\n";
    }
    my $res = testapi::wait_serial(qr/$str-\d+-/, quiet => $args{quiet}, internal_marker => 1);
    die 'PID marker not found' unless ($res =~ m/$str-(\d+)-/);
    return $1;
}

=head2 script_sudo

script_sudo($program, $wait_seconds)

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds

=cut

sub script_sudo ($self, $prog, $wait = 10) {
    my $str;
    if ($wait > 0) {
        $str = testapi::hashed_string("SS$prog$wait");
        $prog = "$prog; echo $str > /dev/$testapi::serialdev";
    }
    testapi::type_string "sudo $prog\n";
    if (testapi::check_screen 'sudo-passwordprompt', 3) {
        testapi::type_password;
        testapi::send_key 'ret';
    }
    if ($str) {
        return testapi::wait_serial($str, $wait, internal_marker => 1);
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

sub script_output ($self, $script, @args) {
    my %args = testapi::compat_args(
        {
            timeout => undef,
            proceed_on_failure => 0,    # fail on error by default
            quiet => undef,
            # 80 is approximate quantity of chars typed during 'curl' approach
            # if script length is lower there is no point to proceed with more complex solution
            type_command => length $script < 80,
        }, ['timeout'], @args);

    my $marker = testapi::hashed_string("SO$script");
    my $script_path = "/tmp/script$marker.sh";

    # prevent use of network for offline installations
    if (testapi::get_var('OFFLINE_SUT')) {
        testapi::record_info('forced type_cmd', 'Forced typing the command as we are offline');
        $args{type_command} = 1;
    }

    if (testapi::is_serial_terminal) {
        my $heretag = 'EOT_' . $marker;
        my $cat = "cat > $script_path << '$heretag'; echo $marker-\$?-";
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
        bmwqemu::log_call("Content of $script_path :\n \"$cat\" \n");
        testapi::type_string $cat . "\n";
        testapi::wait_serial("$cat", no_regex => 1, quiet => $args{quiet});
        # Wait for input prompt of here tag before typing $script. This avoids
        # messy output, like duplicate output of $script. We do this in a second
        # wait_serial() call, to avoid issues during new line detection.
        testapi::wait_serial('> ', no_regex => 1, quiet => $args{quiet});
        testapi::type_string "$script\n$heretag\n";
        testapi::wait_serial("> $heretag", no_regex => 1, quiet => $args{quiet});
        testapi::wait_serial("$marker-0-", quiet => $args{quiet}, internal_marker => 1);
    }
    elsif ($args{type_command}) {
        my $cat = "cat - > $script_path;";
        testapi::type_string $cat;
        testapi::type_string "\n", wait_still_screen => testapi::backend_get_wait_still_screen_on_here_doc_input();
        testapi::type_string $script . "\n", timeout => $args{timeout};
        testapi::send_key('ctrl-d');
    }
    else {
        open my $fh, '>', 'current_script' or croak("Could not open file. $!");
        print $fh $script;
        close $fh;
        testapi::assert_script_run('curl -f -v ' . testapi::autoinst_url('/current_script') . " > $script_path");
        testapi::script_run 'clear';
        unlink 'current_script';
    }

    # Surround the actual script output with special markers so that we can
    # unambiguously separate the expected output from other content that we
    # might encounter on the serial device depending on how it is used in the
    # SUT
    my $shell_cmd = testapi::is_serial_terminal() ? 'bash -oe pipefail' : 'bash -eox pipefail';
    my $run_script = "echo $marker; $shell_cmd $script_path ; echo SCRIPT_FINISHED$marker-\$?-";
    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
        testapi::type_string "$run_script\n";
        testapi::wait_serial($run_script, no_regex => 1, quiet => $args{quiet});
    }
    else {
        testapi::type_string "($run_script) | tee /dev/$testapi::serialdev\n";
    }
    my $output = testapi::wait_serial(qr/SCRIPT_FINISHED$marker-(\d+)-/, capture_name => 'Exit code', timeout => $args{timeout}, record_output => 1, quiet => $args{quiet}, internal_marker => 1)
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

sub set_expected_serial_failures ($self, $failures) {
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

sub set_expected_autoinst_failures ($self, $failures) {
    $self->{autoinst_failures} = $failures;
}

# override
sub activate_console ($self, $console) { }

# override
sub console_selected ($self, $console) { }

=head2 sut_marker

    sut_marker($cmd)

Generate a unique marker string for a command to be used for synchronization
with the SUT. Used primarily for internal testing.

=cut

sub sut_marker ($self, $cmd) {
    my $c = $cmd;
    $c =~ s/^\s+|\s+$//g;
    my $l = length $c;
    my $head = substr $c, 0, 4;
    my $tail = $l >= 4 ? substr $c, -4 : $c;
    return "OA:${head}${l}${tail}";
}

=head2 install_serial_marker_hook

    install_serial_marker_hook($level)

Install shell hooks (like PROMPT_COMMAND) into the SUT to emit synchronization
markers to serial.

=cut

sub install_serial_marker_hook ($self, $level) {
    return if $level < 2;
    my $pc;
    my $dev = "/dev/$testapi::serialdev";
    if ($level == 3) {
        $pc = "PROMPT_COMMAND='ret=\$?; cmd=\$(fc -ln -1 2>/dev/null); printf \"OA:DONE-%04x-%d-%s\\nOA:START\\n\" \$RANDOM \$ret \"\${cmd#\${cmd%%[![:space:]]*}}\" > $dev'";
    }
    else {
        $pc = "PROMPT_COMMAND='if [ -n \"\$__OA_MARK\" ]; then echo \"\${__OA_MARK}-\$?-\" > $dev; unset __OA_MARK; fi; echo \"OA:START\" > $dev'";
    }
    testapi::type_string "$pc\n";
    my $marker_match = 'OA:START';
    my $hook_cmd = "for f in ~/.bashrc ~/.profile; do grep -q '$marker_match' \"\$f\" 2>/dev/null || cat <<'EOF' >> \"\$f\"\n$pc\nEOF\ndone\n";
    testapi::type_string $hook_cmd;
    my $console = testapi::current_console() // 'sut';
    $self->{_serial_marker_hook_installed}->{$console} = 1;
}

=head2 _detect_serial_marker_capability

    _detect_serial_marker_capability()

Detect the SUT's shell capabilities for pretty serial markers.
Returns:
- 1: Fallback (classic markers)
- 2: Basic bash (PROMPT_COMMAND support)
- 3: Advanced bash (PROMPT_COMMAND + history/fc support)

=cut

sub _detect_serial_marker_capability ($self) {
    my $console = testapi::current_console() // 'sut';
    if (my $level = $self->{_serial_marker_level}->{$console}) {
        return $level if $level < 2 || $self->{_serial_marker_hook_installed}->{$console};

        $self->install_serial_marker_hook($level);
        return $level;
    }

    my $level = 1;
    my $pretty = testapi::get_var('PRETTY_SERIAL_MARKER');
    my $serial_term = testapi::is_serial_terminal();
    return $self->{_serial_marker_level}->{$console} = $level if !$pretty || $serial_term;

    testapi::type_string "echo \"BASH:\$BASH_VERSION:\" > /dev/$testapi::serialdev\n";
    my $out = testapi::wait_serial(qr/BASH:([^:]*):/, 10);
    if ($out && $out =~ /BASH:(?:[3-9]|\d{2,})/) {
        $level = 2;
        # Check if bash and history features are available to use pretty serial markers
        testapi::type_string "type fc && set -o | grep -q 'history.*on' && echo \"FC:OK:\" > /dev/$testapi::serialdev\n";
        if (testapi::wait_serial(qr/FC:OK:/, 10)) {
            $level = 3;
        }
        $self->install_serial_marker_hook($level);
        bmwqemu::log_call("serial_marker: console '$console' Level $level detected");
    }
    else {
        bmwqemu::log_call("serial_marker: console '$console' Level 1 detected (fallback)");
        return 1;
    }
    return $self->{_serial_marker_level}->{$console} = $level;
}

1;
