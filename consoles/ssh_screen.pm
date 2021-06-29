# Copyright © 2019-2021 SUSE LLC
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

package consoles::ssh_screen;

use Mojo::Base 'consoles::serial_screen', -signatures;
use Carp 'croak';
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';

has ssh_connection => undef;
has ssh_channel    => undef;

use constant TYPE_STRING_TIMEOUT => 60;

sub new ($class) {
    my $self = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;

    croak('Missing parameter ssh_connection') unless $self->ssh_connection;
    croak('Missing parameter ssh_channel')    unless $self->ssh_channel;

    if ($self->{logfile}) {
        open($self->{loghandle}, ">>", $self->{logfile})
          or croak('Cannot open logfile ' . $self->{logfile});
    }

    return $self->SUPER::new($self->ssh_channel);
}

sub do_read ($self, undef, %args) {
    my $buffer = '';
    $args{timeout}  //= undef;    # wait till data is available
    $args{max_size} //= 2048;

    croak('We expect to get a none blocking SSH channel') if ($self->ssh_channel->blocking());
    my $stime = consoles::serial_screen::thetime();
    while (!$args{timeout} || (consoles::serial_screen::elapsed($stime) < $args{timeout})) {
        my $read = $self->ssh_channel->read($buffer, $args{max_size});
        if (defined($read)) {
            $_[1] = $buffer;
            print {$self->{loghandle}} $buffer if $self->{loghandle};
            return $read;
        }

        last if ($args{timeout} == 0);
        select(undef, undef, undef, 0.25);
    }
    return undef;
}

sub type_string ($self, $nargs) {
    bmwqemu::log_call(%$nargs);

    my $text           = $nargs->{text};
    my $terminate_with = $nargs->{terminate_with} // '';
    my $written        = 0;
    my $stime          = consoles::serial_screen::thetime();

    $text .= "\cC" if ($terminate_with eq 'ETX');

    while ($written < length($text)) {
        my $elapsed = consoles::serial_screen::elapsed($stime);

        croak("type_screen(): Timed out after $elapsed seconds.")
          if ($elapsed > TYPE_STRING_TIMEOUT);

        my $chunk = $self->ssh_channel->write(substr($text, $written));

        if (!defined($chunk)) {
            my ($errcode, $errname, $errstr) = $self->ssh_connection->error;

            croak "Lost SSH connection to SUT: $errstr"
              if $errcode != LIBSSH2_ERROR_EAGAIN;
            select(undef, undef, undef, 0.1);
        } elsif ($chunk < 0) {
            # Old Net::SSH2 error signaling
            croak "Lost SSH connection to SUT"
              if $chunk != LIBSSH2_ERROR_EAGAIN;
            select(undef, undef, undef, 0.1);
        } else {
            $written += $chunk;
        }
    }

    $self->ssh_channel->send_eof if ($terminate_with eq 'EOT');
}

1;
