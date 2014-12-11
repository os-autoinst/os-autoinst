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

use English;

sub init() {
    my $self = shift;

    ## TODO make this configurable in vars.json
    ## $self->{terminal} = [qw(s3270)]; # non-interactive
    $self->{terminal} = [qw(x3270 -script)]; # interactive

    $self->{zVMhost}     = "zvm54";
    $self->{guest_user}  = "linux154";
    $self->{guest_login} = "lin390";
    
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
	command_output => ($#out_array > 2) ? join("\n", @out_array[0..$#out_array-2]) : '',
	status_3270 => $out_array[-2],
	status_command => $out_array[-1]
    };

    cluck "command not 'ok'" if $out->{status_command} ne "ok";

    return $out;
}

sub expect_3270() {
    my ($self, $command, %arg) = @_;

    if (!exists $arg{status_command_match}) { $arg{status_command_match} = "ok" } ;

    confess "status_command_match must be 'ok' or 'error'" 
	unless (($arg{status_command_match} eq "ok") || ($arg{status_command_match} eq "error"));

    my $result = $self->pump_3270_script($command);

    if ($result->{status_command} ne $arg{status_command_match}) {
	cluck "expected command exit status $arg{status_command_match}, got $result->{status_command}";
    };

    if (exists $arg{status_3270_match} && ! $result->{status_3270} =~ $arg{status_3270_match}) {
	cluck "expected 3270 status $arg{status_3270_match}, got $result->{status_3270}";
    };

    if (exists $arg{result_filter}) { $arg{result_filter}($result->{command_output})  };

    if (exists $arg{result_match} && ! $result->{command_output} =~ $arg{result_match}) { 
	cluck "expected command output '$arg{result_match}', got '$result->{command_output}'";
    };

    $result;
}

sub strip_data() {
    $_[0] =~ s/^data: //mg;
    $_[0] =~ s/^ +\n//mg;
}

sub sequence_3270() {
    my ($self, @commands) = @_;

    
    foreach my $command (@commands) {
	say $command;
	say @commands;
	$self->pump_3270_script($command);
    }

    $self->pump_3270_script("Wait(InputField)");
    $self->pump_3270_script("Snap");
    my $result = $self->expect_3270("Snap(Ascii)", result_filter => \&strip_data );
    $result;
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

    if ($r->{command_output} =~ /RECONNECT.*/) {
	cluck "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
	sleep 30;
	die say $r->{command_output};
    } elsif ($r->{command_output} =~ "HCPLGA054E.*") {
	cluck "machine $self->{zVMhost} $self->{guest_login} in use ('$&').";
	sleep 30;
	die say $r->{command_output};
    } # else { say $r->{command_output}; }
    ;

    $r = $self->sequence_3270(qw{
String(ftpboot)
ENTER 
});

    sleep 30;

    exit;
}

1;
