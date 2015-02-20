package backend::vnc_backend;
use strict;
use base ('backend::baseclass');

use Time::HiRes qw(usleep gettimeofday);

use feature qw/say/;
use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

sub fetch_all_pending_screenshots() {
    my ($self, $timeout, $min_time) = @_;

    return unless $self->{'vnc'};

    eval {$self->{'vnc'}->update_framebuffer($timeout, $min_time);};

    if ($@) {
        bmwqemu::diag "VNC failed $@";
        $self->close_pipes();
    }

    return unless $self->{'vnc'}->_framebuffer;

    $self->enqueue_screenshot($self->{'vnc'}->_framebuffer);
}

# this is called for all sockets ready to read from. return 1 if socket
# detected and -1 if there was an error
sub check_socket {
    my ($self, $fh) = @_;

    if ($self->{'vnc'}) {
        if ( $fh == $self->{'vnc'}->socket ) {
            $self->fetch_all_pending_screenshots();
            return 1;
        }
    }
    # This was not for me.  Try baseclass.
    return $self->SUPER::check_socket($fh);
}

sub close_pipes() {
    my ($self) = @_;

    close($self->{'vnc'}->socket) if ($self->{'vnc'} && $self->{'vnc'}->socket);
    $self->{'vnc'} = undef;

    $self->SUPER::close_pipes();
}

# to be overwritten e.g. in qemu to check stderr
sub special_socket($) {
    return 0;
}

sub type_string($$) {
    my ($self, $args) = @_;

    for my $letter (split( "", $args->{text}) ) {
        $letter = $self->map_letter($letter);
        $self->{'vnc'}->send_mapped_key($letter);
        $self->fetch_all_pending_screenshots(.5, .05);
    }
    $self->fetch_all_pending_screenshots(.2);
    return {};
}

sub send_key($) {
    my ($self, $args) = @_;

    bmwqemu::diag "send_mapped_key '" . $args->{key} . "'";
    $self->{'vnc'}->send_mapped_key($args->{key});
    $self->fetch_all_pending_screenshots(.2);
    return {};
}

sub mouse_hide {
    my ($self, $args) = @_;

    $self->{'mouse'}->{'x'} = $self->{'vnc'}->width - 1;
    $self->{'mouse'}->{'y'} = $self->{'vnc'}->height - 1;

    my $border_offset = int($args->{border_offset});
    $self->{'mouse'}->{'x'} -= $border_offset;
    $self->{'mouse'}->{'y'} -= $border_offset;

    bmwqemu::diag "mouse_move $self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'}";
    $self->{'vnc'}->mouse_move_to($self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'});
    return { 'absolute' => $self->{'vnc'}->absolute };

}

sub mouse_set {
    my ($self, $args) = @_;

    # TODO: for framebuffers larger than 1024x768, we need to upscale
    $self->{'mouse'}->{'x'} = int($args->{x});
    $self->{'mouse'}->{'y'} = int($args->{y});

    bmwqemu::diag "mouse_set $self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'}";
    $self->{'vnc'}->mouse_move_to($self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'});
    return {};
}

sub mouse_button {
    my ($self, $args) = @_;

    my $button = $args->{button};
    my $bstate = $args->{bstate};

    my $mask = 0;
    if ($button eq 'left') {
        $mask = $bstate;
    }
    elsif ($button eq 'right') {
        $mask = $bstate << 2;
    }
    elsif ($button eq 'middle') {
        $mask = $bstate << 1;
    }
    bmwqemu::diag "pointer_event $mask $self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'}";
    $self->{'vnc'}->send_pointer_event( $mask, $self->{'mouse'}->{'x'}, $self->{'mouse'}->{'y'} );
    return {};
}

1;
