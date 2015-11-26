# this is an abstract class
package backend::baseclass;
use strict;
use warnings;
use threads;
use Carp qw(cluck carp confess);
use JSON qw( to_json );
use File::Copy qw(cp);
use File::Basename;
use Time::HiRes qw(gettimeofday);
use bmwqemu;
use IO::Select;

use Data::Dumper;
use feature qw(say);

my $framecounter = 0;    # screenshot counter
our $MAGIC_PIPE_CLOSE_STRING = "xxxQUITxxx\n";

# should be a singleton - and only useful in backend thread
our $backend;

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    $self->{started} = 0;
    return $self;
}

# runs in the thread to deserialize VNC commands
sub handle_command {

    my ($self, $cmd) = @_;

    my $func = $cmd->{cmd};
    unless ($self->can($func)) {
        die "not supported command: $func";
    }
    return $self->$func($cmd->{arguments});
}

sub die_handler {
    my $msg = shift;
    #print STDERR "DIE $msg\n";
    cluck "DIE $msg\n";
    $backend->stop_vm();
    $backend->close_pipes();
}


use parent qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
    qw(
      update_request_interval last_update_request
      screenshot_interval last_screenshot)
);

sub run {
    my ($self, $cmdpipe, $rsppipe) = @_;

    die "there can be only one!" if $backend;
    $backend = $self;

    # register consoles
    require consoles::localXvnc;
    consoles::localXvnc->new($backend);

    require consoles::vnc_base;
    consoles::vnc_base->new($backend);

    require consoles::s3270;
    consoles::s3270->new($backend);

    require consoles::sshXtermVt;
    consoles::sshXtermVt->new($backend);

    require consoles::sshX3270;
    consoles::sshX3270->new($backend);

    require consoles::remoteVnc;
    consoles::remoteVnc->new($backend);

    $SIG{__DIE__} = \&die_handler;

    my $io = IO::Handle->new();
    $io->fdopen($cmdpipe, "r") || die "r fdopen $!";
    $self->{cmdpipe} = $io;

    $io = IO::Handle->new();
    $io->fdopen($rsppipe, "w") || die "w fdopen $!";
    $rsppipe = $io;
    $io->autoflush(1);
    $self->{rsppipe} = $io;

    printf STDERR "$$: cmdpipe %d, rsppipe %d\n", fileno($self->{cmdpipe}), fileno($self->{rsppipe});

    bmwqemu::diag "started mgmt loop with thread id " . threads->tid();

    $self->{select} = IO::Select->new();
    $self->{select}->add($self->{cmdpipe});

    $self->last_update_request("-Inf" + 0);
    $self->last_screenshot("-Inf" + 0);
    $self->screenshot_interval($bmwqemu::vars{SCREENSHOTINTERVAL} || .5);
    $self->update_request_interval($self->screenshot_interval());

    $self->run_capture_loop($self->{select});

    bmwqemu::diag("management thread exit at " . POSIX::strftime("%F %T", gmtime));
}

use List::Util qw(min);

=head2 run_capture_loop(\@select, $timeout, $update_request_interval, $screenshot_interval)

=out

=item select

IO::Select object that is polled when given

=item timout

run the loop this long in seconds, indefinitely if undef, or until the
$self->{cmdpipe} is closed, whichever occurs first.

=item update_request_interval

space out update polls for this interval in seconds, i.e. update the
internal buffers this often.

If unset, use $self->{update_request_interval}.  For the main capture
loop $self->{update_request_interval} can be modified while this loop
is running, e.g. to poll more often for a stretch of time.

=item screenshot_interval

space out screen captures for this interval in seconds, i.e. save a
screenshot from the buffers this often.

If unset, use $self->{screenshot_interval}.  For the main capture
loop, $self->{screenshot_interval} can be modified while this loop is
running, e.g. to do some fast or slow motion.

=back

=cut

sub run_capture_loop {
    my ($self, $select, $timeout, $update_request_interval, $screenshot_interval) = @_;
    my $starttime = gettimeofday;
    # say Dumper $self;
    eval {
        while (1) {

            last if (!$self->{cmdpipe});

            my $now = gettimeofday;

            my $time_to_timeout = "Inf" + 0;
            if (defined $timeout) {
                $time_to_timeout = $timeout - ($now - $starttime);
                #say "time_to_timeout=$time_to_timeout";

                last if $time_to_timeout <= 0;
            }

            my $time_to_update_request = ($update_request_interval // $self->update_request_interval) - ($now - $self->last_update_request);
            #say "time_to_update_request=$time_to_update_request";

            if ($time_to_update_request <= 0) {
                $self->request_screen_update();
                $self->last_update_request($now);
                $time_to_update_request = ($update_request_interval // $self->update_request_interval);
            }

            my $time_to_screenshot = ($screenshot_interval // $self->screenshot_interval) - ($now - $self->last_screenshot);
            #say "time_to_screenshot=$time_to_screenshot";

            if ($time_to_screenshot <= 0) {
                $self->capture_screenshot();
                $self->last_screenshot($now);
                $time_to_screenshot = ($screenshot_interval // $self->screenshot_interval);
            }

            my $time_to_next = min($time_to_screenshot, $time_to_update_request, $time_to_timeout);
            #say "time_to_next=$time_to_next";

            if (defined $select) {
                my @ready = $select->can_read($time_to_next);

                for my $fh (@ready) {
                    unless ($self->check_socket($fh)) {
                        die "huh! $fh\n";
                    }
                }
            }
            else {
                # "select" used to emulate "sleep"
                # (coolo) no idea why susanne did this
                select(undef, undef, undef, $time_to_next);    ## no critic
                                                               #usleep($time_to_next * 1_000_000);
            }
        }
    };

    if ($@) {
        bmwqemu::diag "capure loop failed $@";
        $self->close_pipes();
    }
}

# new api

sub start_encoder {
    my ($self) = @_;

    return if $bmwqemu::vars{NOVIDEO};

    my $cwd = Cwd::getcwd();
    open($self->{encoder_pipe}, "|-", "nice -n 19 $bmwqemu::scriptdir/videoencoder $cwd/video.ogv")
      || die "can't call $bmwqemu::scriptdir/videoencoder";
}

sub get_last_mouse_set {
    my $self = shift;
    return $self->{mouse};
}

sub post_start_hook {
    my ($self) = @_;

    # ignored by default
    return 0;
}

sub start_vm {
    my ($self) = @_;
    $self->{mouse} = {x => undef, y => undef};
    $self->{started} = 1;
    $self->start_encoder();
    return $self->do_start_vm();
}

sub stop_vm {
    my $self = shift;
    if ($self->{started}) {
        close($self->{encoder_pipe}) if $self->{encoder_pipe};
        unlink('backend.run');
        $self->do_stop_vm();
        $self->{started} = 0;
    }
    $self->close_pipes();    # does not return
    return {};
}

sub alive {
    my $self = shift;
    if ($self->{started}) {
        if ($self->file_alive() and $self->raw_alive()) {
            return 1;
        }
        else {
            bmwqemu::diag("ALARM: backend.run got deleted! - exiting...");
            alarm 3;
        }
    }
    return 0;
}

my $iscrashedfile = 'backend.crashed';
sub unlink_crash_file {
    unlink($iscrashedfile) if -e $iscrashedfile;
}

sub write_crash_file {
    if (open(my $fh, ">", $iscrashedfile)) {
        print $fh "crashed\n";
        close $fh;
    }
    else {
        warn "cannot write '$iscrashedfile'";
    }
}

# new api end

# virtual methods
sub notimplemented() { confess "backend method not implemented" }

sub power {

    # parameters: acpi, reset, (on), off
    notimplemented;
}

sub insert_cd { notimplemented }
sub eject_cd  { notimplemented }

sub do_start_vm {
    # start up the vm
    notimplemented;
}

sub do_stop_vm { notimplemented }

sub stop              { notimplemented }
sub cont              { notimplemented }
sub do_savevm         { notimplemented }
sub do_loadvm         { notimplemented }
sub do_extract_assets { notimplemented }
sub status            { notimplemented }

## MAY be overwritten:

sub get_backend_info {

    # returns hashref
    my ($self) = @_;
    return {};
}

sub cpu_stat {

    # vm's would return
    # (userstat, systemstat)
    return [];
}

my $lastscreenshot;
my $lastscreenshotName;

sub enqueue_screenshot {
    my ($self, $image) = @_;

    return unless $image;

    ## FIXME: is this still needed?
    ## don't overdo it
    #my $interval = $self->screenshot_interval();
    #my $rest = $interval - $self->elapsed_time();
    #return unless $rest < 0.05;
    #$self->reset_timer();

    $image = $image->scale(1024, 768);

    $framecounter++;

    my $filename = $bmwqemu::screenshotpath . sprintf("/shot-%010d.png", $framecounter);
    my $lastlink = $bmwqemu::screenshotpath . "/last.png";

    #print STDERR $filename,"\n";

    # link identical files to save space
    my $sim = 0;
    $sim = $lastscreenshot->similarity($image) if $lastscreenshot;

    #bmwqemu::diag "similarity is $sim";
    # 54 is based on t/data/user-settings-*
    if ($sim > 54) {
        symlink(basename($lastscreenshotName), $filename) || warn "failed to create $filename symlink: $!\n";
    }
    else {    # new
        $image->write($filename) || die "write $filename";
        # copy new one to shared directory, remove old one and change symlink
        $bmwqemu::screenshotQueue->enqueue($filename);
        $lastscreenshot     = $image;
        $lastscreenshotName = $filename;
        unlink($lastlink);
        symlink(basename($lastscreenshotName), $lastlink);
        #my $ocr=get_ocr($image);
        #if($ocr) { diag "ocr: $ocr" }
    }
    if ($self->{encoder_pipe}) {
        if ($sim > 50) {    # we ignore smaller differences
            $self->{encoder_pipe}->print("R\n");
        }
        else {
            $self->{encoder_pipe}->print("E $lastscreenshotName\n");
        }
        $self->{encoder_pipe}->flush();
    }
}

sub close_pipes {
    my ($self) = @_;

    if ($self->{cmdpipe}) {
        close($self->{cmdpipe}) || die "close $!\n";
        $self->{cmdpipe} = undef;
    }

    return unless $self->{rsppipe};

    # XXX: perl does not really close the fd here due to threads!?
    print "sending magic and exit\n";
    $self->{rsppipe}->print($MAGIC_PIPE_CLOSE_STRING);
    close($self->{rsppipe}) || die "close $!\n";
    threads->exit();
}

# this is called for all sockets ready to read from
sub check_socket {
    my ($self, $fh) = @_;

    if ($self->{cmdpipe} && $fh == $self->{cmdpipe}) {
        my $cmd = backend::driver::_read_json($self->{cmdpipe});

        if ($cmd->{cmd}) {
            my $rsp = $self->handle_command($cmd);
            #CORE::say __FILE__.":".__LINE__.":" . bmwqemu::pp($cmd) . " : ".bmwqemu::pp($rsp);
            if ($self->{rsppipe}) {    # the command might have closed it
                $self->{rsppipe}->print(JSON::to_json({rsp => $rsp}));
                $self->{rsppipe}->print("\n");
            }
        }
        else {
            use Data::Dumper;
            die "no command in " . Dumper($cmd);
        }
        return 1;
    }
    return 0;
}

###################################################################
## access other consoles from the test case thread

sub activate_console {
    my ($self, $args) = @_;
    my ($testapi_console, $backend_console, $console_args) = @$args{qw(testapi_console backend_console backend_args)};

    if (exists $self->{consoles}->{$testapi_console}) {
        die "activate_console: console $testapi_console already activated";
    }

    if (!$self->{console_classes}->{$backend_console}) {
        die "new_console: console class $backend_console unknown";
    }
    my $new_console = $self->{console_classes}->{$backend_console};
    $new_console->activate($testapi_console, $console_args);

    #CORE::say __FILE__. ":" . __LINE__ . ":" . bmwqemu::pp($new_console);

    $self->{consoles}->{$testapi_console} = $new_console;
    $self->select_console($args);

    # don't return any complex object - this needs to be transferred through JSON to the test thread
    return $testapi_console;
}

# There can be two vnc backends (local Xvnc or remote vnc) and
# there can be several terminals on the local Xvnc.
#
# switching means: turn to the right vnc and if it's the Xvnc,
# iconify/deiconify the right x3270 terminal window.
#
# FIXME? for now, we just raise the terminal window to the front on
# the local-Xvnc DISPLAY.
#
# should we hide the other windows, somehow?
#if exists $self->{current_console} ...
# my $current_window_id = $self->{current_console}->{window_id};
# if (defined $current_window_id) {
#     system("DISPLAY=$display xdotool windowminimize --sync $current_window_id");
# }
#-> select

sub select_console {
    my ($self, $args) = @_;
    #CORE::say __FILE__. ":" . __LINE__ . ":" . bmwqemu::pp($args);
    my $testapi_console = $args->{testapi_console};

    unless (exists $self->{consoles}->{$testapi_console}) {
        die "select_console: console $testapi_console not activated";
    }
    my $selected_console = $self->{consoles}->{$testapi_console};
    #CORE::say __FILE__. ":" . __LINE__ . ":" . bmwqemu::pp($selected_console);
    $selected_console->select;

    $self->{current_console} = $selected_console;
    $self->{current_screen}  = $selected_console->screen;
    $self->capture_screenshot();
    return $testapi_console;
}

sub deactivate_console {
    my ($self, $args) = @_;
    my $testapi_console = $args->{testapi_console};
    unless (exists $self->{consoles}->{$testapi_console}) {
        die "deactivate_console: console $testapi_console not activated";
    }
    my $console_info = $self->{consoles}->{$testapi_console};
    if (defined $self->{current_console} && $self->{current_console} == $console_info) {
        $self->{current_console} = undef;
    }
    $self->{consoles}->{$testapi_console}->disable();
    delete $self->{consoles}->{$testapi_console};
    return {};
}

sub request_screen_update() {
    my ($self) = @_;

    return $self->bouncer('request_screen_update', undef);
}

sub bouncer() {
    my ($self, $call, $args) = @_;
    # forward to the current VNC console
    return unless $self->{current_screen};
    #CORE::say __FILE__.":".__LINE__.": $call, ".bmwqemu::pp($args);
    return $self->{current_screen}->$call($args);
}

sub send_key() {
    my ($self, $args) = @_;
    return $self->bouncer('send_key', $args);
}

sub type_string() {
    my ($self, $args) = @_;
    return $self->bouncer('type_string', $args);
}

sub mouse_set() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_set', $args);
}

sub mouse_hide() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_hide', $args);
}

sub mouse_button() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_button', $args);
}


sub capture_screenshot {
    my ($self) = @_;
    return unless $self->{current_screen};

    my $screen = $self->{current_screen}->current_screen();
    $self->enqueue_screenshot($screen) if $screen;
    return;
}

###################################################################
# this is used by backend::console_proxy
sub proxy_console_call {
    my ($self, $wrapped_call) = @_;

    my ($console, $function, $args) = @$wrapped_call{qw(console function args)};

    my $wrapped_result = {};

    eval {
        # Do not die in here.
        # Move the decision to actually die to the server side instead.
        # For this ignore backend::baseclass::die_handler.
        local $SIG{__DIE__} = 'DEFAULT';
        $wrapped_result->{result} = $self->{consoles}->{$console}->$function(@$args);
    };

    if ($@) {
        $wrapped_result->{exception} = join("\n", bmwqemu::pp($wrapped_call), $@);
        # cluck "proxy_console_call: exception caught in the backend thread\n$@\n";
    }

    return $wrapped_result;
}


1;
# vim: set sw=4 et:
