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

sub pump_3270_script() {
    my ($self, $command) = @_;

    $self->{in}  .= $command . "\n";
    $self->{connection}->pump until  $self->{out} =~ /C\($self->{zVMhost}\)/;

    my $out_string = $self->{out};
    $self->{out} = "";		# flush the IPC output, IPC will only append

    # split in three pieces: command status, terminal status and
    # command output, if any.
    my @out_array = split(/\n/, $out_string);

    my $out = {
	command_output => ($#out_array > 2) ? [@out_array[0..$#out_array-2]] : [],
	status_3270 => $out_array[-2],
	status_command => $out_array[-1]
    };

    return $out;
}

sub expect_3270() {
    my ($self, $command, %arg) = @_;

    if (!exists $arg{status_command_match}) { $arg{status_command_match} = "ok" } ;

    confess "status_command_match must be 'ok' or 'error' or 'any'"
	unless ($arg{status_command_match} ~~ ['ok', 'error', 'any'] ); # TODO: should use grep here?

    my $result = $self->pump_3270_script($command);

    if ($arg{status_command_match} ne 'any' and $result->{status_command} ne $arg{status_command_match}) {
	croak "expected command exit status $arg{status_command_match}, got $result->{status_command}";
    };

    if (exists $arg{status_3270_match} && ! $result->{status_3270} ~~ $arg{status_3270_match}) {
	croak "expected 3270 status $arg{status_3270_match}, got $result->{status_3270}";
    };

    if (exists $arg{result_filter}) {
	$arg{result_filter}($result->{command_output});
    };

    if (exists $arg{result_match} && ! $result->{command_output} ~~ $arg{result_match}) {
	croak "expected command output '$arg{result_match}', got '$result->{command_output}'";
    };

    $result;
}
sub strip_data() {
    my ($lines) = @_;

    foreach my $line (@$lines) {
	$line =~ s/^data: //mg;
	$line =~ s/^ +\n//mg;
    }

}

sub grab_more_until_running() {
    my ($self) = @_;

    $self->pump_3270_script("Snap");
    my $snap = $self->expect_3270("Snap(Ascii)", result_filter => \&strip_data );

    my $result = $snap->{command_output};

    while (@$result[-1] =~ /MORE\.\.\./) {
	$self->pump_3270_script("Clear");
	$self->pump_3270_script("Snap");
	$snap = $self->expect_3270("Snap(Ascii)", result_filter => \&strip_data );

	splice $result, -1, 1, $snap->{command_output};
    }


    $snap->{command_output} = $result;

    $snap;
}


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
