# Copyright (C) 2017 SUSE LLC
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
# You should have received a copy of the GNU General Public License

package osutils;

require 5.002;
use strict;
use warnings;

use Carp;
use base 'Exporter';
use Mojo::File 'path';
use bmwqemu 'diag';
use POSIX ':sys_wait_h';
use Symbol 'gensym';
use IPC::Open3;
use IO::Select;

our @EXPORT_OK = qw(
  dd_gen_params
  find_bin
  gen_params
  qv
  quote
  runcmd
  runcmd_output
  attempt
);

# An helper to lookup into a folder and find an executable file between given candidates
# First argument is the directory, the remainining are the candidates.
sub find_bin {
    my ($dir, @candidates) = @_;

    foreach my $t_bin (map { path($dir, $_) } @candidates) {
        return $t_bin if -e $t_bin && -x $t_bin;
    }
    return;
}

## no critic
# An helper to full a parameter list, typically used to build option arguments for executing external programs.
# mimics perl's push, this why it's a prototype: first argument is the array, second is the argument option and the third is the parameter.
# the (optional) hash argument which can include the prefix argument for the array, if not specified '-' (dash) is assumed by default
# and if parameter should not be quoted, for that one can use no_quotes. NOTE: this is applicable for string parameters only.
# if the parameter is equal to "", the value is not pushed to the array.
# For example: gen_params \@params, 'device', 'scsi', prefix => '--', no_quotes => 1;
sub gen_params(\@$$;%) {
    my ($array, $argument, $parameter, %args) = @_;

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
sub dd_gen_params(\@$$) {
    my ($array, $argument, $parameter) = @_;
    gen_params(@{$array}, $argument, $parameter, prefix => "--");
}

# It merely splits a string into pieces interpolating variables inside it.
# e.g.  gen_params @params, 'drive', "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}" can be rewritten as
#       gen_params @params, 'drive', [qv "file=$basedir/l$i cache=unsafe if=none id=hd$i format=$vars->{HDDFORMAT}"]
sub qv($) {
    split /\s+|\h+|\r+/, $_[0];
}

# Add single quote mark to string
# Mainly use in the case of multiple kernel parameters to be passed to the -append option
# and they need to be quoted using single or double quotes
sub quote {
    "\'" . $_[0] . "\'";
}

sub opencmd {
    my ($params, $sub) = @_;
    my ($pid, $status);

    local $SIG{CHLD} = sub {
        local ($!, $?);
        while ((my $child = waitpid(-1, WNOHANG)) > 0) {
            diag "runcmd pid $pid returned $child";
            $status = $?;
        }
    };

    my ($wtr, $rdr, $err);
    $err = gensym;
    $pid = open3($wtr, $rdr, $err, @$params);
    die "couldn't open: $!" unless defined $pid;
    close($wtr) or die "couldn't close fh: $!";

    $sub->($rdr, $err);

    close($rdr) or die "couldn't close fh: $!";
    close($err) or die "couldn't close fh: $!";

    my $exit_code = $status >> 8;
    die "runcmd failed with exit code $exit_code" unless ($exit_code == 0);
    return $exit_code;
}

# Open a process to run external program and check its return status
sub runcmd {
    diag "running " . join(' ', @_);

    return opencmd(\@_, sub {
            my ($rdr, $err) = @_;
            my $s = IO::Select->new();

            $s->add($rdr, $err);
            while (my @ready = $s->can_read()) {
                for my $fh (@ready) {
                    if (sysread($fh, my $buf, 4096)) {
                        diag $buf if ($fh == $rdr);
                        diag $buf if ($fh == $err);
                    }
                    else {
                        $s->remove($fh);
                    }
                }
            }
    });
}

sub runcmd_output {
    diag "running " . join(' ', @_);
    my $out = '';

    opencmd(\@_, sub {
            my ($rdr, $err) = @_;
            my $s = IO::Select->new();

            $s->add($rdr, $err);
            while (my @ready = $s->can_read()) {
                for my $fh (@ready) {
                    if (sysread($fh, my $buf, 4096)) {
                        $out .= $buf if ($fh == $rdr);
                        diag $buf if ($fh == $err);
                    }
                    else {
                        $s->remove($fh);
                    }
                }
            }
    });

    return $out;
}
## use critic

sub attempt {
    my $attempts = 0;
    my ($total_attempts, $condition, $cb, $or) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(attempts condition cb or)}) : @_;
    until ($condition->() || $attempts >= $total_attempts) {
        warn "Attempt $attempts";
        $cb->();
        sleep 1;
        $attempts++;
    }
    $or->() if $or && !$condition->();
    warn "Attempts terminated!";
}

1;
