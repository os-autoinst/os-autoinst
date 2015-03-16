#!/usr/bin/perl -w
package backend::s390x::s3270;

use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw(zVM_host guest_user guest_login));

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;


require IPC::Run;

use IPC::Run::Debug; # set IPCRUNDEBUG=data in shell environment for trace

use Thread::Queue;


sub new() {

    my $self = Class::Accessor::new(@_);

    return $self;
}

sub start() {
    my $self = shift;

    # prepare the communication queue
    $self->{raw_expect_queue} = new Thread::Queue();

    # start the local terminal emulator
    $self->{in} = "";
    $self->{out} = "";
    $self->{err} = "";

    $self->{connection} = IPC::Run::start(\@{$self->{s3270}},\$self->{in},\$self->{out},\$self->{err} );

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


sub send_3270() {
    my ($self, $command, %arg) = @_;

    if (!exists $arg{command_status}) { $arg{command_status} = "ok" }
    confess "command_status must be 'ok' or 'error' or 'any', got $arg{command_status}."
      unless (grep $arg{command_status}, ['ok', 'error', 'any'] );

    $self->{in}  .= $command . "\n";
    $self->{connection}->IPC::Run::pump until  $self->{out} =~ /^(ok|error)/mg;

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

###################################################################
# expect_3270
#       [, buffer_full => qr/MORE\.\.\./]
#       [, buffer_ready => qr/RUNNING/ ]
#       [, output_delim => "one-line NEEDLE"]
#       [, flush_lines => qr/^ +$/]
#       [, timeout => 1 ]
#       [, clear_buffer => 0 ]

# Pretend the 3270 was a serial terminal where you can wait for some
# specific output to show up.  Return all output up to that match.
# Save remaining screen content for the next call.

# Assume the screen to be partitioned in three areas:
#    output (all but the last two lines)
#    input  (second to last line)
#    status (last line)

# If no output_delim is given, return as soon as the expected status
# is reached (expected_status matches).

# If the status line matches 'buffer_full', hit clear to get a re-draw
# of pending further output, until the status line matches
# 'buffer_ready'.

# Flush all lines matching 'flush_lines'.

# Return stretch from last expect_3270 call up to & including line
# matching 'output_delim', as array of lines.

# flush history since last expect_3270 call if(clear_buffer)

# return [] when timed out.

sub expect_3270() {
    my ($self, %arg) = @_;
    ### say Dumper \%arg;

    $arg{buffer_full}	//= qr/MORE\.\.\./;
    $arg{buffer_ready}	//= qr/RUNNING/;
    $arg{timeout}	//= 7;
    $arg{clear_buffer}	//= 0;
    $arg{output_delim}  //= undef;
    if (!exists $arg{flush_lines}) {
        $arg{flush_lines} = qr/^ +$/;
    }

    ### say Dumper \%arg;

    if ($arg{clear_buffer}) {
        my $n = $self->{raw_expect_queue}->pending();
        if ($n) {
            $self->{raw_expect_queue}->dequeue_nb($n);
        }
    }

    my $result = [];

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

            my $status_line  = pop @$co;
            my $input_line   = pop @$co;
            my @output_area  = @$co;


            if (defined $arg{flush_lines}) {
                ### say Dumper $arg{flush_lines};
                @output_area = grep !/$arg{flush_lines}/, @output_area;
            }

            if (@output_area > 0) {
                $self->{raw_expect_queue}->enqueue(@output_area);
                $we_had_new_output = 1;
            }

            ### say Dumper $self->{raw_expect_queue};

            # if there is MORE..., go and grab it.
            if ($status_line =~ /$arg{buffer_full}/) {
                $self->send_3270("Clear");
                next;
            }

            ### say Dumper \@output_area;
            ### say Dumper $input_line;
            ### say Dumper $status_line;

            # If the status line is not buffer_ready, some computation
            # is still going on.  Wait for more Output.

            if ($status_line !~ /$arg{buffer_ready}/) {
                # if the timeout is not over, wait for more output
                my $elapsed_time = time() - $start_time;
                if ($elapsed_time < $arg{timeout}) {
                    if ($self->wait_output($arg{timeout} - $elapsed_time)) {
                        next;
                    }
                }

                # flush the buffer for debugging:
                while (my $line = $self->{raw_expect_queue}->dequeue_nb()) {
                    push @$result, $line;
                }

                confess "status line matches neither buffer_ready nor buffer_full:\n".Dumper($result).$status_line;
            }

        }

        # No more host output is pending.  The status line matches
        # buffer_ready.  We have some output in the raw_expect_queue,
        # possibly from a previous run, btw!

        # If we are looking for an output_delimiter, look for that.
        if (!defined $arg{output_delim}) {
            # no need to wait for something special.  just return what you have...
            while (my $line = $self->{raw_expect_queue}->dequeue_nb()) {
                push @$result, $line;
            }
            last;
        }

        my $line;
        while ($line = $self->{raw_expect_queue}->dequeue_nb()) {
            push @$result, $line;
            if (!defined $line || $line =~ /$arg{output_delim}/) {
                last;
            }
        }

        # If we matched the 'output_delim', we are done.
        if (defined $line) {
            last;
        }

        # The queue is empty!

        # If we got so far and we had some output on the screen the
        # last time, clear the screen so we don't grab the same stuff
        # again.

        # The maybe better alternative solution to the same problem
        # would be to remember lines that were not updated since the
        # last Snap(Ascii) and to thus avoid duplicate lines.

        # for now we live with having a clear screen.

        if ($we_had_new_output) {
            $self->send_3270("Clear");
        }

        ### say "===================================================================";
        ### say Dumper %arg;

        # wait for new output from the host.
        my $elapsed_time = time() - $start_time;
        if ($elapsed_time > $arg{timeout}
            || !$self->wait_output($arg{timeout} - $elapsed_time))
        {
            confess "expect_3270: timed out.\n"."  waiting for ${\Dumper \%arg}\n"."  last output:\n".Dumper($result);
        }
        next;

    }

    # tracing output
    say Dumper $result;
    return $result;
}



sub wait_output() {
    my ($self, $timeout) = @_;
    $timeout //= 0;		# just poll
    my $r = $self->send_3270("Wait($timeout,Output)", command_status=>'any');

    if ($r->{command_status} eq 'ok') {
        return 1;
    }
    else {
        return 0
          unless $r->{command_output}[0] ne 'Wait: Timed out';
        confess "has the s3270 wait timeout failure response changed?\n". Dumper $r;
    }


}

###################################################################

sub sequence_3270() {
    my ($self, @commands) = @_;


    foreach my $command (@commands) {
        $self->send_3270($command);
    }

}


sub nice_3270_status() {
    my ($status_string) = @_;
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
        'command_execution_time'
          ## The time that it took for the host to respond to the
          ## previous commnd, in seconds with milliseconds after the
          ## decimal. If the previous command did not require a host
          ## response, this is a dash.
    );

    my %nice_status;
    @nice_status{@status_names} = @raw_status;

    ##return wantarray ? %nice_status : \%nice_status ;
    my $retval = \%nice_status;

    return $retval;
}


###################################################################
# connect to the host
sub _connect_3270() {
    my ($self, $host) = @_;

    my $r = $self->send_3270("Connect($host)");

    if ($r->{terminal_status} !~ / C\($host\) / ) {
        confess"connect to host >$host< failed.\n".join("\n", @$r);
    }

    $self->send_3270("Wait(InputField)");

    $r = $self->expect_3270();

    if (!grep /Fill in your USERID and PASSWORD and press ENTER/, @$r) {
        confess "doesn't look like zVM login prompt.";
    }

    return $r;
}

###################################################################
# log in
sub _login_guest() {
    my ($self, $guest, $password) = @_;


    $self->send_3270("String($guest)");
    $self->send_3270("String($password)");
    $self->send_3270("ENTER");
    $self->send_3270("Wait(InputField)");

    # Depending on which application is running on the host vm guest,
    # we get various status lines:
    my $r = $self->expect_3270(buffer_ready => qr/(?:(?:CP|VM) READ|RUNNING)/);

    return $r;
}

sub cp_logoff_disconnect() {
    my ($self) = @_;

    # #cp force logoff immediate ??
    $self->send_3270('String("#cp logoff")');
    $self->send_3270('ENTER');
    $self->send_3270('Wait(Disconnect)');

}

sub cp_disconnect() {
    my ($self) = @_;

    $self->send_3270('String("#cp disconnect")');
    $self->send_3270('ENTER');
    $self->send_3270('Wait(Disconnect)');
}

sub connect_and_login() {
    my ($self, $reconnect_ok) = @_;
    $reconnect_ok //= 0;
    my $r;
    ###################################################################
    # try to connect exactly twice
    for (my $count = 0; $count += 1; ) {

        $r = $self->_connect_3270($self->{zVM_host});

        $r = $self->_login_guest($self->{guest_user}, $self->{guest_login});

        # bail out if the host is in use
        # currently:  KILL THE GUEST
        # TODO:  think about what to really do in this case.

        if (grep /(?:RECONNECT|HCPLGA).*/, @$r ) {
            cluck #
              "connect_and_login: machine is in use ($self->{zVM_host} $self->{guest_login}):\n" . #
              join("\n", @$r) . "\n";

            if ($count == 2) {
                die #
                  "Could not reclaim guest despite hard_shutdown.  this is odd.\n". #
                  "Is this machine possibly connected on another terminal?\n";
            }

            last if $reconnect_ok;

            # shut down and reconnect
            carp "trying hard shutdown...\n";
            $self->cp_logoff_disconnect();

            next;
        }

        last;

    }
}

1;
