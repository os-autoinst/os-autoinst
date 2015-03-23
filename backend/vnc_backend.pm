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
    # drain the VNC socket before polling for a ne update
    $self->{vnc}->update_framebuffer();
    $self->{vnc}->send_update_request();
}

sub capture_screenshot($ ) {
    my ($self) = @_;
    return unless $self->{'vnc'};

    unless ($self->{'vnc'}->_framebuffer) {
        # No _framebuffer yet.  First connect?  Tickle vnc server to
        # get it filled.
        $self->request_screen_update();
        usleep(5_000);
    }

    $self->{vnc}->update_framebuffer();
    return unless $self->{'vnc'}->_framebuffer;
    $self->enqueue_screenshot($self->{'vnc'}->_framebuffer);
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

    # speed limit: 15bps.  VNC has key up and key down over the wire,
    # not whole key press events.  So with a faster pace, the vnc
    # server may think of contact bounces for repeating keys.
    my $seconds_per_keypress = 1/15;

    # further slow down if being asked for.
    # 250 = magic default from testapi.pm (FIXME: wouldn't undef just do?)

    # FIXME: the intended use of max_interval is the bootloader.  The
    # bootloader prompt drops characters when typing quickly.  This
    # problem mostly occurs in the bootloader.  Humans notice because
    # they look at the screen while typing.  So this loop should be
    # replaced by some true 'looking at the screen while typing',
    # e.g. waiting for no more screen updates 'in the right area'.
    # For now, just waiting is good enough: The slow-down only affects
    # the bootloader sequence.
    if (($args->{max_interval} // 250) < 250) {
        # according to 	  git grep "type_string.*, *[0-9]"  on
        #   https://github.com/os-autoinst/os-autoinst-distri-opensuse,
        # typical max_interval values are
        #   4ish:  veeery slow
        #   15ish: slow
        $seconds_per_keypress = $seconds_per_keypress + 1/sqrt( $args->{max_interval} );
    }

    for my $letter (split( "", $args->{text}) ) {
        $letter = $self->map_letter($letter);
        $self->{'vnc'}->send_mapped_key($letter);
        $self->run_capture_loop(undef, $seconds_per_keypress, $seconds_per_keypress*.9);
    }
    return {};
}

sub send_key($) {
    my ($self, $args) = @_;

    bmwqemu::diag "send_mapped_key '" . $args->{key} . "'";
    # FIXME the max_interval logic from type_string should go here, no?
    # and really, the screen should be checked for settling after key press...
    $self->{'vnc'}->send_mapped_key($args->{key});
    $self->run_capture_loop(undef, .2, .19);
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
