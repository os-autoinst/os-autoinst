package backend::vnc_backend;
use strict;
use base ('backend::baseclass');

use Time::HiRes qw(usleep gettimeofday);

use feature qw/say/;
use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

sub request_screen_update($ ) {
    my ($self) = @_;
    return unless $self->{'vnc'};
    $self->{vnc}->send_update_request();
}

sub capture_screenshot($ ) {
    my ($self) = @_;
    return unless $self->{'vnc'};
    $self->{vnc}->fetch_pending_updates();
    return unless $self->{'vnc'}->_framebuffer;
    $self->enqueue_screenshot($self->{'vnc'}->_framebuffer);
}

sub update_framebuffer() { # fka capture
    my ($self) = @_;
    $self->request_screen_update();
    $self->capture_screenshot();
}

# this is called for all sockets ready to read from. return 1 for success.
sub check_socket {
    my ($self, $fh) = @_;

    if ($self->{'vnc'}) {
        if ( $fh == $self->{'vnc'}->socket ) {
            # FIXME: polling the VNC socket is not part of the backend
            # select loop, because IO::Select and read() should not be
            # mixed, according to the docs.  So this should be dead
            # code.  Remove once no tests die here for a while.
            die "this should be dead code.";
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
        $self->run_capture_loop(undef, .1, .03);
    }
    return {};
}

sub send_key($) {
    my ($self, $args) = @_;

    bmwqemu::diag "send_mapped_key '" . $args->{key} . "'";
    $self->{'vnc'}->send_mapped_key($args->{key});
    $self->run_capture_loop(undef, .1, .03);
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
