# Copyright 2017-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package osutils;

use Mojo::Base 'Exporter', -signatures;
use Carp;
use List::Util 'first';
use Mojo::File 'path';
use bmwqemu;
use Mojo::IOLoop::ReadWriteProcess 'process';

our @EXPORT_OK = qw(
  dd_gen_params
  find_bin
  gen_params
  qv
  quote
  runcmd
  run
  run_diag
  attempt
);

# An helper to lookup into a folder and find an executable file between given candidates
# First argument is the directory, the remainining are the candidates.
sub find_bin ($dir, @candidates) { first { -e && -x } map { path($dir, $_) } @candidates }

# An helper to full a parameter list, typically used to build option arguments for executing external programs.
# if the parameter is equal to "", the value is not pushed to the array.
sub gen_params ($array, $argument, $parameter = undef, %args) {
    return unless ($parameter);
    $args{prefix} = "-" unless $args{prefix};

    if (ref($parameter) eq "") {
        $parameter = quote($parameter) if $parameter =~ /\s+/ && !$args{no_quotes};
        push(@$array, $args{prefix} . "${argument}", $parameter);
    }
    elsif (ref($parameter) eq "ARRAY") {
        push(@$array, $args{prefix} . "${argument}", join(',', @$parameter));
    }

}

# doubledash shortcut version. Same can be achieved with gen_params.
sub dd_gen_params ($array, $argument, $parameter) {
    gen_params($array, $argument, $parameter, prefix => "--");
}

# It merely splits a string into pieces interpolating variables inside it.
# e.g.  gen_params \@params, 'drive', "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}" can be rewritten as
#       gen_params \@params, 'drive', [qv "file=$basedir/l$i cache=unsafe if=none id=hd$i format=$vars->{HDDFORMAT}"]
sub qv ($string) { split /\s+|\h+|\r+/, $string }

# Add single quote mark to string
# Mainly use in the case of multiple kernel parameters to be passed to the -append option
# and they need to be quoted using single or double quotes
sub quote ($string) { "'$string'" }

sub run (@args) {
    bmwqemu::diag "running `@args`";
    my $p = process(execute => shift @args, args => [@args]);
    $p->quirkiness(1)->separate_err(0)->start()->wait_stop();

    my $stdout = join('', $p->read_stream->getlines());
    chomp $stdout;

    close($p->$_ ? $p->$_ : ()) for qw(read_stream write_stream error_stream);

    return $p->exit_status, $stdout;
}

# Do not check for anything - just execute and print
sub run_diag (@args) {
    my ($exit_status, $output);
    eval {
        local $SIG{__DIE__} = undef;
        ($exit_status, $output) = run(@args);
        bmwqemu::diag("Command `@args` terminated with $exit_status" . (length($output) ? "\n$output" : ''));
    };
    bmwqemu::diag("Fatal error in command `@args`: $@") if ($@);
    return $output;
}

# Open a process to run external program and check its return status
sub runcmd (@cmd) {
    my ($e, $out) = run(@cmd);
    bmwqemu::diag $out if $out && length($out) > 0;
    die "runcmd '" . join(' ', @cmd) . "' failed with exit code $e" . ($out ? ": '$out'" : '') unless $e == 0;
    return $e;
}

## use critic

sub wait_attempt () { sleep($ENV{OSUTILS_WAIT_ATTEMPT_INTERVAL} // 1) }

sub attempt {    # no:style:signatures
    my $attempts = 0;
    my ($total_attempts, $condition, $cb, $or) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(attempts condition cb or)}) : @_;
    until ($condition->() || $attempts >= $total_attempts) {
        bmwqemu::diag "Waiting for $attempts attempts";
        $cb->();
        wait_attempt;
        $attempts++;
    }
    $or->() if $or && !$condition->();
    bmwqemu::diag "Finished after $attempts attempts";
}

1;
