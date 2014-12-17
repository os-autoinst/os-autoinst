#!/usr/bin/perl -w
package backend::s390x;
use base ('backend::baseclass');

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;

use IPC::Run qw(start pump finish);

use IPC::Run::Debug; # set IPCRUNDEBUG=data in shell environment for trace



sub init() {
    my $self = shift;

    ## TODO make this configurable in vars.json somehow?  is there a --debug flag?

    # TODO figure what to do with the traces in non-interactive mode
    ## $self->{terminal} = [qw(s3270)]; # non-interactive
    $self->{terminal} = [qw(x3270 -script -trace -set screenTrace -charset us)]; # interactive

    # TODO: where to get these vars from? ==> vars.json
    $self->{zVMhost}     = "zvm54";
    $self->{guest_user}  = "linux154";
    $self->{guest_login} = "lin390";

    # TODO ftp/nfs/hhtp/https
    # TODO dasd/iSCSI/SCSI
    # TODO osa/hsi/ctc
    
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

    if (!exists $arg{command_status}) { $arg{command_status} = "ok" } ;
    confess "command_status must be 'ok' or 'error' or 'any', got $arg{command_status}."
	unless (grep $arg{command_status}, ['ok', 'error', 'any'] );

    $self->{in}  .= $command . "\n";
    $self->{connection}->pump until  $self->{out} =~ /^(ok|error)/mg;

    # grab and flush the IPC output.  IPC will only append, so the out
    # var needs to be flushed.
    my $out_string = $self->{out};
    $self->{out} = "";

    # split output in three pieces: command status, terminal status
    # and command output, if any.
    my @out_array = split(/\n/, $out_string);

    my $out = {
	command_output => ($#out_array > 1) ? [@out_array[0..$#out_array-2]] : [],
	terminal_status => $out_array[-2],
	command_status => $out_array[-1]
    };

    foreach my $line (@{$out->{command_output}}) {
	$line =~ s/^data: //;
    }

    if ($arg{command_status} ne 'any' and $out->{command_status} ne $arg{command_status}) {
	confess "expected command exit status $arg{command_status}, got $out->{command_status}";
    };

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
    $arg{timeout}	//= 1;
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

	# grab any pending output
	if ($self->wait_output()) {
	    $self->send_3270("Snap");
	    $r = $self->send_3270("Snap(Ascii)");

	    # split it according to the screen sections
	    my $co = $r->{command_output};

	    my @output_area  = @$co[0..@$co-3];
	    my $input_line   = @$co[-2];
	    my $status_line  = @$co[-1];


	    if (defined $arg{flush_lines}) {
		### say Dumper $arg{flush_lines};
		@output_area = grep ! /$arg{flush_lines}/, @output_area;
	    }

	    # enqueue what you found
	    $self->{raw_expect_queue}->enqueue(@output_area);

	    ### say Dumper $self->{raw_expect_queue};

	    # if there is MORE..., go and grab it.
	    if ($status_line =~ $arg{buffer_full}) {
		$self->send_3270("Clear");
		next ;
	    }

	    ### say Dumper \@output_area;
	    ### say Dumper $input_line;
	    ### say Dumper $status_line;

	    # If the status line is not buffer_ready, some computation
	    # is still going on.  Wait for more Output.

	    if ($status_line !~ $arg{buffer_ready}) {
		# if the timeout is not over, wait for more output
		my $elapsed_time = time() - $start_time;
		if ($elapsed_time < $arg{timeout}) {
		    if ($self->wait_output($arg{timeout} - $elapsed_time)) {
			next;
		    }
		}
		confess "status line matches neither buffer_ready nor buffer_full:\n>$status_line<";
	    };

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
	    return $result;
	}

	my $line;
	while ($line = $self->{raw_expect_queue}->dequeue_nb()) {
	    push @$result, $line;
	    if (!defined $line || $line =~ $arg{output_delim}) {
		last;
	    }
	}

	# If we matched the 'output_delim', we are done.
	if (defined $line) {
	    return $result;
	}

	# The queue is empty!

	# wait for new output from the host.
	
	### say "===================================================================";
	### say Dumper %arg;

	my $elapsed_time = time() - $start_time;
	if ($elapsed_time > $arg{timeout} 
	    || !$self->wait_output($arg{timeout} - $elapsed_time)) {
	    confess "timed out";
	}
	next;



    };

    confess "can't get here...";
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
	$self->pump_3270_script($command);
    }

    $self->pump_3270_script("Wait(InputField)"); # is this the best wait for the host to have settled?

    my $result = $self->grab_more_until_running();

    $result;
}


sub nice_3270_status() {
    my ($status_string) = @_ ;
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

sub do_start_vm($) {
    my $self = shift;
    # start console
    $self ->{ in } = "";
    $self ->{ out} = "";
    $self ->{ err} = "";

    $self->{connection} = start (
	\@{$self->{terminal}},
	\$self->{in},
	\$self->{out},
	\$self->{err} );

    # TODO: should we use this?  Toggle(AidWait,clear)\n

    #
    $self->expect_3270("Connect($self->{zVMhost})",
		       status_3270_match => "C($self->{zVMhost})");

    $self->expect_3270("Wait(InputField)");
    $self->expect_3270("Snap");

    $self->expect_3270("Snap(Ascii)",
		       result_match => "Fill in your USERID and PASSWORD and press ENTER",
		       result_filter => \&strip_data);

    $self->expect_3270("String($self->{guest_user})");
    $self->expect_3270("String($self->{guest_login})");
    $self->expect_3270("ENTER");
    $self->expect_3270("Wait(InputField)");
    $self->expect_3270("Snap");

    my $r = $self->expect_3270("Snap(Ascii)", result_filter => \&strip_data);

    if ($r->{command_output} ~~ /RECONNECT.*/) {
	### for now, pause, to interactively kill the guest!!
	## TODO:  only do this in debug
	say "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
	$self->pump_3270_script('String("#cp logo")');
	$self->pump_3270_script('ENTER');
	$self->pump_3270_script('Wait(Disconnect)');
	sleep 2;
	croak "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
    } elsif ($r->{command_output} ~~ /HCPLGA054E.*/) {
	### for now, pause, to interactively kill the guest!!
	## TODO:  only do this in debug
	say "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
	$self->pump_3270_script('String("#cp logo")');
	$self->pump_3270_script('ENTER');
	$self->pump_3270_script('Wait(Disconnect)');
	sleep 2;
	croak "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
    } # else { say $r->{command_output}; }
    ;

    ###################################################################
    # ftpboot

    $r = $self->sequence_3270(qw{
String(ftpboot)
ENTER
Wait(InputField)
});

    # CLEANME:  make ftpboot function
    my ($s, $cursor_row, $row);
    ##############################
    # choose server

    # why can't I just call this function?  why do I need & ??
    $s = &nice_3270_status($r->{status_3270});

    $cursor_row = $s->{cursor_row};

    while ( ($row, my $content) = each($r->{command_output})) {
    	if ($content =~ /DIST\.SUSE\.DE/) {
    	    last;
    	}
    };

    my $sequence = ["Home", ("Down") x ($row-$cursor_row), "ENTER", "Wait(InputField)"];
    say "\$sequence=@$sequence";

    $r = $self->sequence_3270(@$sequence);

    ##############################
    # choose distribution

    $s = &nice_3270_status($r->{status_3270});

    $cursor_row = $s->{cursor_row};

    while ( ($row, my $content) = each($r->{command_output})) {
    	if ($content =~ /SLES-11-SP4-Alpha2/) {
    	    last;
    	}
    };

    my $sequence = ["Home", ("Down") x ($row-$cursor_row), "ENTER", "Wait(InputField)"];
    say "\$sequence=@$sequence";

    $r = $self->sequence_3270(@$sequence);

    ##############################
    # parmfile editing

    # for now just add the ssh parameter, so we can always connect to
    # the system under test

    # TODO wait for the editor
    
#     $self->sequence_3270(qw(
# String(INPUT) ENTER
# String(ssh) ENTER ENTER
# String(FILE) ENTER
# ));
     $self->sequence_3270(qw(
String(FILE) ENTER
));

    # Now wait for linuxrc to come up...

    ###################################################################
    # linuxrc
    

    sleep 50;

}

1;
