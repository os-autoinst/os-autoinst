#!/usr/bin/perl -w
package backend::s390x;
use strict;
use warnings;

use base ('backend::baseclass');

use feature qw/say/;

use IPC::Run qw(start pump finish);

use IPC::Run::Debug; # use IPCRUNDEBUG=data in shell environment for trace

use Data::Dumper qw(Dumper);

use Carp qw(confess cluck carp);

sub init($) {
    my $self = shift;

    ## TODO make this configurable in vars.json
    ## $self->{terminal} = [qw(s3270)]; # non-interactive
    $self->{terminal} = [qw(x3270 -script)]; # interactive

    $self->{zVMhost}     = "zvm54";
    $self->{guest_user}  = "linux154";
    $self->{guest_login} = "lin390";
    
}

sub pump_3270_script($$) {
    my ($self, $command) = @_;

    $self->{in}  .= $command . "\n";
    $self->{connection}->pump until  $self->{out} =~ /C\($self->{zVMhost}\)/;

    my $out_string = $self->{out};
    $self->{out} = "";		# flush the IPC output, IPC will only append

    # split in three pieces: command status, terminal status and
    # command output, if any.
    my @out_array = split(/\n/, $out_string);

    my $out = {
	command_output => ($#out_array > 2) ? join("\n", @out_array[0..$#out_array-2]) : '',
	status_3270 => $out_array[-2],
	status_command => $out_array[-1]
    };

    cluck "command not 'ok'" if $out->{status_command} ne "ok";

    return $out;
}

sub expect_3270() {
    my ($self, $command, $result_match, $status_3270_match, $status_command_match) = @_;

    if (!defined $status_command_match) { $status_command_match = "ok" } ;

    confess "status_command_match must be 'ok' or 'error'" 
	unless (($status_command_match eq "ok") || ($status_command_match eq "error"));

    my $result = $self->pump_3270_script($command);

    cluck "expected command exit status $status_command_match, got $result->{status_command}" 
    	if $result->{status_command} ne $status_command_match;

    cluck "expected 3270 status $status_3270_match, got $result->{status_3270}"
    	unless defined $status_3270_match && $result->{status_3270} =~ $status_3270_match;

    if (defined $result_match && $result->{command_output} =~ $result_match) { 
	cluck "expected command output '$result_match', got '$result->{command_output}'";
    };

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
    $self->expect_3270("Connect($self->{zVMhost})", undef, "C\\($self->{zVMhost}\\)");
    $self->pump_3270_script("Wait(InputField)");
    $self->pump_3270_script("Snap");

    $self->expect_3270("Snap(Ascii)", "Fill in your USERID and PASSWORD and press ENTER");

    $self->pump_3270_script("String($self->{guest_user})");
    $self->pump_3270_script("String($self->{guest_login})");
    $self->pump_3270_script("ENTER");
    $self->pump_3270_script("Wait(InputField)");
    $self->pump_3270_script("Snap");

    my $r = $self->pump_3270_script("Snap(Ascii)"); # instead wait for "LOGON AT"

    $r->{command_output} =~ s/^data: //mg;

    if ($r->{command_output} =~ "RECONNECTED.*") {
	cluck "machine $self->{zVMhost} $self->{guest_login} in use ('$`$&').";
	say $r->{command_output};
    } elsif ($r->{command_output} =~ "HCPLGA054E.*") {
	cluck "machine $self->{zVMhost} $self->{guest_login} in use ('$`$&').";
	say $r->{command_output};
    } # else { say $r->{command_output}; }
    ;

    sleep 30;

    exit;
}

1;
