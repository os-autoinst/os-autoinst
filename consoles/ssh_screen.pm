# Copyright 2019-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::ssh_screen;

use Mojo::Base 'consoles::serial_screen', -signatures;
use Carp 'croak';
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use Time::Seconds;

has ssh_connection => undef;
has ssh_channel => undef;

use constant TYPE_STRING_TIMEOUT => ONE_MINUTE;

sub new ($class, @args) {
    my $self = bless @args ? @args > 1 ? {@args} : {%{$args[0]}} : {}, ref $class || $class;

    croak('Missing parameter ssh_connection') unless $self->ssh_connection;
    croak('Missing parameter ssh_channel') unless $self->ssh_channel;

    if ($self->{logfile}) {
        open($self->{loghandle}, ">>", $self->{logfile})
          or croak('Cannot open logfile ' . $self->{logfile});
    }

    return $self->SUPER::new($self->ssh_channel);
}

sub do_read {    # no:style:signatures
    my ($self, undef, %args) = @_;
    my $buffer = '';
    my %error_seen = (LIBSSH2_ERROR_EAGAIN => 1);
    $args{timeout} //= undef;    # wait till data is available
    $args{max_size} //= 2048;

    croak('We expect to get a none blocking SSH channel') if ($self->ssh_channel->blocking());
    my $stime = consoles::serial_screen::thetime();
    while (!$args{timeout} || (consoles::serial_screen::elapsed($stime) < $args{timeout})) {
        my $read = $self->ssh_channel->read($buffer, $args{max_size});
        if (defined($read)) {
            # this is why we can't use a signature for this function,
            # assigning to @_ in a function with signature triggers a
            # warning
            $_[1] = $buffer;
            print {$self->{loghandle}} $buffer if $self->{loghandle};
            return $read;
        }

        my ($errcode, $errname, $errstr) = $self->ssh_connection->error;
        bmwqemu::diag("SSH read error: $errcode $errstr")
          unless $error_seen{$errcode}++;

        last if ($args{timeout} == 0);
        select(undef, undef, undef, 0.25);
    }
    return undef;
}

sub type_string ($self, $nargs) {
    bmwqemu::log_call(%$nargs, $nargs->{secret} ? (-masked => $nargs->{text}) : ());

    my $text = $nargs->{text};
    my $terminate_with = $nargs->{terminate_with} // '';
    my $written = 0;
    my $stime = consoles::serial_screen::thetime();

    $text .= "\cC" if ($terminate_with eq 'ETX');

    while ($written < length($text)) {
        my $elapsed = consoles::serial_screen::elapsed($stime);

        croak((caller(0))[3] . ": Timed out after $elapsed seconds.")
          if ($elapsed > TYPE_STRING_TIMEOUT);

        my $chunk = $self->ssh_channel->write(substr($text, $written));

        if (!defined($chunk)) {
            my ($errcode, $errname, $errstr) = $self->ssh_connection->error;

            croak "Lost SSH connection to SUT: $errcode $errstr"
              if $errcode != LIBSSH2_ERROR_EAGAIN;
            select(undef, undef, undef, 0.1);
        } elsif ($chunk < 0) {
            # Old Net::SSH2 error signaling
            croak "Lost SSH connection to SUT: $chunk"
              if $chunk != LIBSSH2_ERROR_EAGAIN;
            select(undef, undef, undef, 0.1);
        } else {
            $written += $chunk;
        }
    }

    $self->ssh_channel->send_eof if ($terminate_with eq 'EOT');
}

1;
