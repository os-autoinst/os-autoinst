#!/usr/bin/perl -w
package backend::s390x;
use base ('backend::baseclass');

use backend::s390x::s3270;
use backend::s390x::get_to_yast;

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;

use IPC::Run qw(start pump finish);

use IPC::Run::Debug; # set IPCRUNDEBUG=data in shell environment for trace

use Thread::Queue;

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


    $self->{raw_expect_queue} = new Thread::Queue();
    $self->{cooked_expect_queue} = new Thread::Queue();

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

	my $we_had_new_output = 0;

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

	    if (@output_area > 0) {
		$self->{raw_expect_queue}->enqueue(@output_area);
		$we_had_new_output = 1;
	    }

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
	    last;
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
	    || !$self->wait_output($arg{timeout} - $elapsed_time)) {
	    confess "timed out";
	}
	next;



    };

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
###################################################################
# linuxrc helpers

sub linuxrc_menu() {
    my ($self, $menu_title, $menu_entry) = @_;
    # get the menu (ends with /^>/)
    my $r = $self->expect_3270(output_delim => qr/^> /);
    ### say Dumper $r;

    # newline separate list of strings when interpolating...
    local $LIST_SEPARATOR = "\n";

    if (! grep /^$menu_title/, @$r) {
	confess "menu does not match expected menu title ${menu_title}\n @${r}";
    }

    my @match_entry = grep /\) $menu_entry/, @$r;

    if (!@match_entry) {
	confess "menu does not contain expected menu entry ${menu_entry}:\n@${r}";
    }

    my ($match_id) = $match_entry[0] =~ /(\d+)\)/;

    my $sequence = ["Clear", "String($match_id)", "ENTER"];

    $self->sequence_3270(@$sequence);
};

sub linuxrc_prompt () {
    my ($self, $prompt, %arg) = @_;

    $arg{value}   //= '';
    $arg{timeout} //= 1;

    my $r = $self->expect_3270(output_delim => qr/(?:\[.*?\])?> /, timeout => $arg{timeout});

    ### say Dumper $r;

    # two lines or more
    # [previous repsonse]
    # PROMPT
    # [more PROMPT]
    # [\[EXPECTED_RESPONSE\]]>

    # newline separate list of strings when interpolating...
    local $LIST_SEPARATOR = "\n";

    if (! grep /^$prompt/, @$r[0..(@$r-1)] ) {
	confess 
	    "prompt does not match expected prompt (${prompt}) :\n".
	    "@$r";
    }

    my $sequence = ["Clear", "String($arg{value})", "ENTER"];
    push @$sequence, "ENTER" if $arg{value} eq '';

    $self->sequence_3270(@$sequence);

};

###################################################################
# connect to the host
sub connect_3270() {
    my ($self, $host) = @_;

    my $r = $self->send_3270("Connect($host)");

    local $LIST_SEPARATOR='\n';
    if ($r->{terminal_status} !~ / C\($host\) / ) {
	confess 
	    "connect to host >$host< failed.\n".
	    "@$r";
    }

    $self->send_3270("Wait(InputField)");

    $r = $self->expect_3270();

    if (! grep /Fill in your USERID and PASSWORD and press ENTER/, @$r) {
	confess "doesn't look like zVM login prompt."
    };

    return $r;
}

###################################################################
# log in
sub login_guest() {
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

sub hard_shutdown_guest() {
    my ($self) = @_;
    
    $self->send_3270('String("#cp logo")');
    $self->send_3270('ENTER');
    $self->send_3270('Wait(Disconnect)');
}

sub ftpboot_menu () {
    my ($self, $menu_entry) = @_;
    # helper vars
    my ($r, $s, $cursor_row, $row);

    # choose server

    $r = $self->send_3270("Home");
    # Why can't I just call this function?  why do I need & ??
    $s = &nice_3270_status($r->{terminal_status});

    $cursor_row = $s->{cursor_row};

    $r = $self->expect_3270(clear_buffer => 1, flush_lines => undef, buffer_ready => qr/PF3=QUIT/);
    ### say Dumper @$r;

    while ( ($row, my $content) = each(@$r)) {
    	if ($content =~ $menu_entry) {
    	    last;
    	}
    };

    my $sequence = ["Home", ("Down") x ($row-$cursor_row), "ENTER", "Wait(InputField)"];
    ## say "\$sequence=@$sequence";

    $self->sequence_3270(@$sequence);

    return $r;
    say $r;
}

###################################################################
sub do_start_vm() {
    my $self = shift;

    # start the local terminal emulator
    $self ->{ in } = "";
    $self ->{ out} = "";
    $self ->{ err} = "";

    $self->{connection} = start (
	\@{$self->{terminal}},
	\$self->{in},
	\$self->{out},
	\$self->{err} );

    # general purpose host response
    my $r;

    ###################################################################
    # TODO:  anything below this line should go to test cases!!

    ###################################################################
    # try to connect exactly twice
    for (my $count = 0; $count += 1; ) {

	$r = $self->connect_3270($self->{zVMhost});

	$r = $self->login_guest($self->{guest_user}, $self->{guest_login});

	# In this function, the array we output is the screenshot lines:
	local $LIST_SEPARATOR = "\n";

	# bail out if the host is in use
	# currently:  KILL THE GUEST
	# TODO:  think about what to really do in this case.

	if (grep /(?:RECONNECT|HCPLGA).*/, @$r ) {
	    cluck # carp 
		"machine $self->{zVMhost} $self->{guest_login} is in use ('$&').".
		"@$r";

	    if ($count >1) {
		die "could not reclaim guest despite hard_shutdown.  this is odd.";
	    }

	    # shut down and reconnect
	    $self->hard_shutdown_guest();

	    next;
	};

	last;
	
    }

    ###################################################################
    # ftpboot

    $self->sequence_3270(qw{
        String(ftpboot)
	ENTER
	Wait(InputField)
    });

    $r = $self->ftpboot_menu(qr/\QDIST.SUSE.DE\E/);
    $r = $self->ftpboot_menu(qr/\QSLES-11-SP4-Alpha2\E/);

    ##############################
    # edit parmfile

    $r = $self->expect_3270(buffer_ready => qr/X E D I T/, timeout => 30);

    $self->sequence_3270(qw(
	String(INPUT) ENTER
    ));

    $r = $self->expect_3270(buffer_ready => qr/Input-mode/);
    ### say Dumper $r;

    # can't use qw{} because of space in commands...
    $self->sequence_3270(split /\n/, <<'EO_frickin_boot_parms');
String("HostIP=10.161.185.154/24 Hostname=s390hsi154.suse.de")
Newline
String("Gateway=10.161.185.254 Nameserver=10.160.0.1 Domain=suse.de")
Newline
String(ssh)
Newline
ENTER
ENTER
EO_frickin_boot_parms

    $r = $self->expect_3270(buffer_ready => qr/X E D I T/);

    $self->sequence_3270(qw(
String(FILE) ENTER
));

    ###################################################################
    # linuxrc

    # wait for linuxrc to come up...
    $r = $self->expect_3270(output_delim => qr/>>> Linuxrc/, timeout=>20);
    ### say Dumper $r;

    $self->linuxrc_menu("Main Menu", "Start Installation");
    $self->linuxrc_menu("Start Installation", "Start Installation or Update");
    $self->linuxrc_menu("Choose the source medium", "Network");
    $self->linuxrc_menu("Choose the network protocol", "HTTP");
    $self->linuxrc_menu("Choose the network device", "\QIBM Hipersocket (0.0.7058)\E");
    
    $self->linuxrc_prompt("Device address for read channel");
    $self->linuxrc_prompt("Device address");
    $self->linuxrc_prompt("Device address");

    $self->linuxrc_menu("Enable OSI Layer 2 support", "No");
    $self->linuxrc_menu("Automatic configuration via DHCP", "No");

    # use values from parmfile
    $self->linuxrc_prompt("Enter your IPv4 address");
    $self->linuxrc_prompt("Enter your netmask. For a normal class C network, this is usually 255.255.255.0.");
    $self->linuxrc_prompt("Enter the IP address of the gateway. Leave empty if you don't need one.");
    $self->linuxrc_prompt("Enter your search domains, separated by a space",
	timeout => 10);
    
    $self->linuxrc_prompt(
	"Enter the IP address of your name server. Leave empty if you don't need one",
	timeout => 10);


    $self->linuxrc_prompt("Enter the IP address of the HTTP server",
			  value => "10.160.0.100");
    $self->linuxrc_prompt("Enter the directory on the server",
			  value => "/install/SLP/SLES-11-SP4-Alpha2/s390x/DVD1");
    
    $self->linuxrc_menu(
	"Do you need a username and password to access the HTTP server",
	"No");
	
    $self->linuxrc_menu(
	"Use a HTTP proxy",
	"No");


    $r = $self->expect_3270(
	output_delim => qr/Reading Driver Update/,
	timeout      => 50);

    ### say Dumper $r;
    

    $self->linuxrc_menu(
	"Select the display type",
	"VNC");

    $self->linuxrc_prompt(
	"Enter your VNC password",
	value => "FOOBARBAZ");

    $r = $self->expect_3270(
	output_delim => qr/\Q*** Starting YaST2 ***\E/,
	timeout      => 20);

    ### say Dumper $r;

    ###################################################################
    # now we are ready do connect to vnc and to start the vnc backend...

    while (1) { sleep 50; }

}

1;
