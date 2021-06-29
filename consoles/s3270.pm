# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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

package consoles::s3270;

use Mojo::Base -strict, -signatures;
use feature 'say';

use base 'consoles::localXvnc';

use Class::Accessor 'antlers';
use Data::Dumper 'Dumper';
use Carp qw(confess cluck carp croak);
use testapi 'get_required_var';
require IPC::Run;
use IPC::Run::Debug;    # set IPCRUNDEBUG=data in shell environment for trace
use Thread::Queue;
use Time::HiRes 'usleep';

has zVM_host    => (is => "rw");
has guest_user  => (is => "rw");
has guest_login => (is => "rw");

sub start ($self) {
    # prepare the communication queue
    $self->{raw_expect_queue} = Thread::Queue->new;

    # start the local terminal emulator
    $self->{in}  = "";
    $self->{out} = "";
    $self->{err} = "";

    $self->{connection} = IPC::Run::start(\@{$self->{s3270}}, \$self->{in}, \$self->{out}, \$self->{err});

}

sub finish ($self) {
    IPC::Run::finish($self->{connection});
}

###################################################################
# send_3270 "COMMAND" [,  command_status => 'ok' (default) or 'error' or 'any' ]

# send command, collect result, synchronously.

# returns hash

# {
#    command_status => "ok" or "error"
#    command_output => @"LINES",    # leading "data: " is stripped off the lines, [] if none.
#    terminal_status => "s3270 status line, see man s3270",
# }

sub send_3270 ($self, $command = '', %arg = undef) {
    $arg{command_status} //= "ok";
    confess "command_status must be 'ok' or 'error' or 'any', got $arg{command_status}."
      unless (grep $arg{command_status}, ['ok', 'error', 'any']);

    $self->{in} .= $command . "\n";
    $self->{connection}->IPC::Run::pump until $self->{out} =~ /^(ok|error)/mg;

    # grab and flush the IPC output.  IPC will only append, so the out
    # var needs to be flushed.
    my $out_string = $self->{out};
    $self->{out} = "";

    # split output in three pieces: command status, terminal status
    # and command output, if any.
    my @out_array = split(/\n/, $out_string);

    my $out = {
        command_status  => pop @out_array,
        terminal_status => pop @out_array,
        command_output  => \@out_array,
    };

    foreach my $line (@{$out->{command_output}}) {
        $line =~ s/^data: //;
    }

    if ($arg{command_status} ne 'any' && $out->{command_status} ne $arg{command_status}) {
        confess "expected command exit status $arg{command_status}, got $out->{command_status}";
    }

    return $out;
}

sub ensure_screen_update ($self) {
    # # TODO we capture_screenshot here to ensure
    # # no screen content is lost in the video.  It is
    # # a hacky work around until this loop is properly
    # # integrated with the baseclass run_capture_loop
    $self->{backend}->request_screen_update();
    usleep(5_000);
    $self->{backend}->capture_screenshot();
    $self->send_3270("Clear");
}

###################################################################
# expect_3270
#       [, buffer_full => qr/MORE\.\.\./]
#       [, buffer_ready => qr/RUNNING/ ]
#       [, expected_status => qr/X E D I T/ ]
#       [, output_delim => "one-line NEEDLE"]
#       [, delete_lines => qr/^ +$/]
#       [, timeout => 1 ]
#       [, clear_buffer => 0 ]

# Pretending the 3270 was a serial terminal where you can wait for some
# specific output to show up. Returns all output up to that match.
# Saves remaining screen content for the next call.

# Assuming the screen to be partitioned in three areas:
#    output (all but the last two lines)
#    input  (second to last line)
#    status (last line)

# If no output_delim is given, returns as soon as the expected status
# is reached ('expected_status' matches).

# If the status line matches 'buffer_full', clear is called to get a re-draw
# of pending further output, until the status line matches
# 'buffer_ready'.

# Deletes all lines from buffer matching 'delete_lines'.

# Returns stretch from last expect_3270 call up to & including line
# matching 'output_delim' as array of lines.

# Clears buffer history since last expect_3270 call if(clear_buffer)

# Dies when timing out

# potential point for improvement:
#  - only clear the screen when it's full, not all the time, thus
#    cope with new incremental input in addition to something that
#    is already captured.
sub expect_3270 ($self, %arg) {
    $arg{buffer_full}     //= qr/MORE\.\.\./;
    $arg{buffer_ready}    //= qr/RUNNING/;
    $arg{expected_status} //= $arg{buffer_ready};
    $arg{timeout}         //= 7;
    $arg{clear_buffer}    //= 0;
    $arg{output_delim}    //= undef;
    $arg{delete_lines}    //= qr/^ +$/;

    if ($arg{clear_buffer}) {
        my $n = $self->{raw_expect_queue}->pending();
        $self->{raw_expect_queue}->dequeue_nb($n) if $n;
    }
    my $result     = [];
    my $start_time = time();
    while (1) {
        my $r;

        my $we_had_new_output = 0;

        # grab any pending output
        if ($self->wait_output()) {
            $self->send_3270("Snap");
            $r = $self->send_3270("Snap(Ascii)");

            # split it according to the screen sections
            my $co = $r->{command_output};

            my $status_line = pop @$co;
            my $input_line  = pop @$co;
            my @output_area = @$co;

            @output_area = grep !/$arg{delete_lines}/, @output_area if defined $arg{delete_lines};

            if (@output_area > 0) {
                $self->{raw_expect_queue}->enqueue(@output_area);
                $we_had_new_output = 1;
            }

            say "expect_3270 queue content:\n\t" . join("\n\t", @{$self->{raw_expect_queue}->{queue}});

            # if there is MORE..., go and grab it.
            if ($status_line =~ /$arg{buffer_full}/) {
                $self->ensure_screen_update();
                next;
            }

            if ($status_line !~ /$arg{expected_status}/) {
                # if the timeout is not over, wait for more output
                my $elapsed_time = time() - $start_time;
                next if $elapsed_time < $arg{timeout} && $self->wait_output($arg{timeout} - $elapsed_time);

                # flush the buffer for debugging:
                while (my $line = $self->{raw_expect_queue}->dequeue_nb()) {
                    push @$result, $line;
                }
                confess "expect_3270: timed out waiting for 'expected_status'.\n"
                  . "  waiting for ${\Dumper \%arg}\n"
                  . "  last output:\n"
                  . Dumper($result)
                  . $status_line;
            }

            die "status line must match 'buffer_ready'" unless ($status_line =~ /$arg{buffer_ready}/);
        }

        # No more host output is pending. We have some output in the raw_expect_queue,
        # possibly from a previous run

        # If *not* looking for output_delim, we reached 'buffer_ready' and just return the output buffer
        if (!defined $arg{output_delim}) {
            # no need to wait for something special. We just return what we have...
            while (my $line = $self->{raw_expect_queue}->dequeue_nb()) {
                push @$result, $line;
            }
            last;
        }

        my $line;
        while ($line = $self->{raw_expect_queue}->dequeue_nb()) {
            push @$result, $line;
            last if !defined $line || $line =~ /$arg{output_delim}/;
        }

        # If we matched the 'output_delim', we are done.
        last if defined $line;

        # The queue is empty. If we got so far and we had some output on the
        # screen the last time, clear the screen so we don't grab the same
        # stuff again.

        # TODO The better alternative solution to the same problem
        # would be to remember lines that were not updated since the
        # last Snap(Ascii) and to thus avoid duplicate lines.

        # For now we have to live with having a clear screen.
        $self->ensure_screen_update() if $we_had_new_output;

        # wait for new output from the host.
        my $elapsed_time = time() - $start_time;
        if ($elapsed_time > $arg{timeout}
            || !$self->wait_output($arg{timeout} - $elapsed_time))
        {
            confess "expect_3270: timed out.\n" . "  waiting for ${\Dumper \%arg}\n" . "  last output:\n" . Dumper($result);
        }
    }

    # tracing output
    say 'expect_3270 result: ' . Dumper(\$result);
    return $result;
}

# timeout = 0: just poll
sub wait_output ($self, $timeout = 0) {
    my $r = $self->send_3270("Wait($timeout,Output)", command_status => 'any');
    return 1 if $r->{command_status} eq 'ok';
    return 0 if $r->{command_output}[0] eq 'Wait: Timed out';
    confess "has the s3270 wait timeout failure response changed?\n" . Dumper $r;
}

###################################################################

sub sequence_3270 ($self, @commands) {
    $self->send_3270($_) for (@commands);
}

# map the terminal status of x3270 to a hash
sub nice_3270_status ($self, $status_string) {
    my (@raw_status) = split(" ", $status_string);
    my @status_names = (
        'keyboard_state',
        ## If the keyboard is unlocked, the letter U. If the
        ## keyboard is locked waiting for a response from the
        ## host, or if not connected to a host, the letter L. If
        ## the keyboard is locked because of an operator error
        ## (field overflow, protected field, etc.), the letter E.
        'screen_formatting',
        ## If the screen is formatted, the letter F. If unformatted or
        ## in NVT mode, the letter U.
        'field_protection',
        ## If the field containing the cursor is protected, the
        ## letter P. If unprotected or unformatted, the letter U.
        'connection_state',
        ## If connected to a host, the string
        ## C(hostname). Otherwise, the letter N.
        'emulator_mode',
        ## If connected in 3270 mode, the letter I. If connected
        ## in NVT line mode, the letter L. If connected in NVT
        ## character mode, the letter C. If connected in
        ## unnegotiated mode (no BIND active from the host), the
        ## letter P. If not connected, the letter N.
        'model_number',
        ## (2-5)
        'number_of_rows',
        ## The current number of rows defined on the screen. The
        ## host can request that the emulator use a 24x80 screen,
        ## so this number may be smaller than the maximum number
        ## of rows possible with the current model.
        'number_of_columns',
        ## The current number of columns defined on the screen,
        ## subject to the same difference for rows, above.
        'cursor_row',
        ## The current cursor row (zero-origin).
        'cursor_column',
        ## The current cursor column (zero-origin).
        'window_id',
        ## The X window identifier for the main x3270 window, in
        ## hexadecimal preceded by 0x. For s3270 and c3270, this
        ## is zero.
        'command_execution_time',
        ## The time that it took for the host to respond to the
        ## previous commnd, in seconds with milliseconds after the
        ## decimal. If the previous command did not require a host
        ## response, this is a dash.
    );

    my %nice_status;
    @nice_status{@status_names} = @raw_status;

    return \%nice_status;
}

sub _connect_3270 ($self, $host) {
    my $r = $self->send_3270("Connect($host)");
    confess "connect to host >$host< failed.\n" . join("\n", @$r) if $r->{terminal_status} !~ / C\($host\) /;
    $self->send_3270("Wait(InputField)");
    $r = $self->expect_3270();
    confess "doesn't look like zVM login prompt." unless grep /Fill in your USERID and PASSWORD and press ENTER/, @$r;
    return $r;
}

sub _login_guest ($self, $guest, $password) {
    $self->send_3270("String($guest)");
    $self->send_3270("String($password)");
    $self->send_3270("ENTER");
    $self->send_3270("Wait(InputField)");

    # Depending on which application is running on the host vm guest,
    # we get various status lines:
    my $r = $self->expect_3270(buffer_ready => qr/(?:(?:CP|VM) READ|RUNNING)/);

    return $r;
}

sub cp_logoff_disconnect ($self) {
    # #cp force logoff immediate ??
    $self->send_3270('String("#cp logoff")');
    $self->send_3270('ENTER');
    $self->send_3270('Wait(Disconnect)');

}

sub cp_disconnect ($self) {
    $self->send_3270('String("#cp disconnect")');
    $self->send_3270('ENTER');
    $self->send_3270('Wait(Disconnect)');
}

sub DESTROY ($self) {
    IPC::Run::finish($self->{connection}) if $self->{connection};
}

sub connect_and_login ($self, $reconnect_ok = 0) {
    my $r;
    ###################################################################
    # try to connect exactly trice
    for (my $count = 0; $count += 1;) {
        $r = $self->_connect_3270($self->{zVM_host});
        $r = $self->_login_guest($self->{guest_user}, $self->{guest_login});

        # bail out if the host is in use
        # currently:  KILL THE GUEST
        # this should be fine as s390x guests should be reserved for
        # os-autoinst use

        if (grep { /(?:RECONNECT|HCPLGA).*/ } @$r) {
            carp                                                                                      #
              "connect_and_login: machine is in use ($self->{zVM_host} $self->{guest_login}):\n" .    #
              join("\n", @$r) . "\n";

            if ($count == 2) {
                carp "Still connected, it's s390, so ... let's wait a bit\n";
                # arbitrary
                sleep 7;
            }
            elsif ($count == 3) {
                die "Could not reclaim guest despite hard_shutdown and retrying multiple times. this is odd.\n"
                  . "Is this machine possibly connected on another terminal?\n";
            }

            last if $reconnect_ok;

            carp "trying hard shutdown and reconnect...\n";
            $self->cp_logoff_disconnect();
            next;
        }
        last;
    }
}


###################################################################
# create x3270 terminals, -e ssh ones and true 3270 ones.
sub new_3270_console ($self) {
    $self->{s3270} = [
        qw(x3270),
        "-display", $self->{DISPLAY},
        qw(-script -charset us -xrm x3270.visualBell:true -xrm x3270.keypadOn:false
          -set screenTrace -xrm x3270.traceDir:.
          -trace -xrm x3270.traceMonitor:false),
        # Dark arts: ancient terminals (ansi.64, vt100) don't have an
        # Alt key.  They send Esc + the key instead.  x3270 for
        # whichever reason can't send the Escape keysym, so we have to
        # hard code it here (0x1b).
        '-xrm', 'x3270.keymap.base.nvt:#replace\nAlt<Key>: Key(0x1b) Default()'
    ];
    $self->start();
    my $status = $self->send_3270()->{terminal_status};
    $status = $self->nice_3270_status($status);

    $self->{window_id} = $status->{window_id};
    return;
}

sub activate ($self) {
    $self->SUPER::activate;

    $self->zVM_host(get_required_var("ZVM_HOST"));
    $self->guest_user(get_required_var("ZVM_GUEST"));
    $self->guest_login(get_required_var("ZVM_PASSWORD"));
    $self->new_3270_console;
    $self->connect_and_login;
    return;
}

sub disable ($self) {
    $self->cp_logoff_disconnect();
    $self->_kill_window();
}

1;
