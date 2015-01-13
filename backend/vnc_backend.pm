package backend::vnc_backend;
use strict;
use base ('backend::baseclass');

sub enqueue_screenshot() {
    my ($self, $image) = @_;

    return unless ($self->{'vnc'} && $self->{'vnc'}->_framebuffer);
    $self->SUPER::enqueue_screenshot($self->{'vnc'}->_framebuffer);
    $self->{'vnc'}->send_update_request();
}

# this is called for all sockets ready to read from. return 1 if socket
# detected and -1 if there was an error
sub check_socket {
    my ($self, $fh) = @_;

    if ($self->{'vnc'}) {
        # vnc is non-blocking so just try and it's important we check this here
        # because select won't wake us if the message is already read into the buffer
        eval { $self->{'vnc'}->receive_message(); };
        if ($@) {
            bmwqemu::diag "VNC failed $@";
            $self->close_pipes();
        }
        else {
            $self->enqueue_screenshot;
        }

        if ( $fh == $self->{'vnc'}->socket ) {
            return 1;
        }
    }
    return $self->SUPER::check_socket($fh);
}

sub close_pipes() {
    my ($self) = @_;

    close($self->{'vnc'}->socket) if ($self->{'vnc'} && $self->{'vnc'}->socket);
    $self->{'vnc'} = undef;

    $self->SUPER::close_pipes();
}

use Time::HiRes qw(gettimeofday);

# to be overwritten e.g. in qemu to check stderr
sub special_socket($) {
    return 0;
}

sub wait_for_screen_stall($) {
    my ($self, $s) = @_;

    $self->{'vnc'}->send_update_request;
    my ( $s1, $ms1 ) = gettimeofday;
    while (1) {
        my @ready = $s->can_read(.1);
        last unless @ready;
        for my $fh (@ready) {
            unless (special_socket($fh)) {
                $self->{'vnc'}->receive_message();
                $self->enqueue_screenshot;
            }
        }
        my ( $s2, $usec2 ) = gettimeofday;
        my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
        #bmwqemu::diag "diff $diff";
        # we can't wait longer - in password prompts there is no screen update
        last if ($diff > .8);
    }
    #my ( $s2, $usec2 ) = gettimeofday;
    #my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
    #bmwqemu::diag "done $diff";
    $self->enqueue_screenshot;
}

sub select_for_vnc {
    my ($self) = @_;

    my $s = IO::Select->new();
    $s->add($self->{'vnc'}->socket);
    return $s;
}

sub type_string($$) {
    my ($self, $args) = @_;
    my @letters = split( "", $args->{text} );

    my $s = $self->select_for_vnc();
    for my $letter (@letters) {
        $letter = $self->map_letter($letter);
        $self->{'vnc'}->send_mapped_key($letter);
        $self->wait_for_screen_stall($s);
    }
}

sub send_key($) {
    my ($self, $args) = @_;

    bmwqemu::diag "send_mapped_key '" . $args->{key} . "'";
    $self->{'vnc'}->send_mapped_key($args->{key});
    my $s = IO::Select->new();
    $s->add($self->{'vnc'}->socket);
    $self->wait_for_screen_stall($s);
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
