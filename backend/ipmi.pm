package backend::ipmi;
use strict;
use base ('backend::baseclass');
use threads;
use threads::shared;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use Data::Dumper;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use testapi qw(get_var);
require IPC::System::Simple;
use autodie qw(:all);

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    die "configure WORKER_HOSTNAME e.g. in workers.ini" unless get_var('WORKER_HOSTNAME');
    return $self;
}

use Time::HiRes qw(gettimeofday);

sub ipmi_cmdline {
    my ($self) = @_;

    return ('ipmitool', '-H', $bmwqemu::vars{IPMI_HOSTNAME}, '-U', $bmwqemu::vars{IPMI_USER}, '-P', $bmwqemu::vars{IPMI_PASSWORD});
}

sub ipmitool {
    my ($self, $cmd) = @_;

    my @cmd = $self->ipmi_cmdline();
    push(@cmd, split(/ /, $cmd));

    my $tmp = File::Temp->new(SUFFIX => '.stdout', OPEN => 0);
    $cmd = join(' ', @cmd) . " > $tmp; echo \"DONE-\$?\" >> $tmp\n";
    $self->{consoles}->{worker}->type_string({text => $cmd});

    my $time = 0;
    while ($time++ < 10) {
        sleep(1);
        open(my $fh, '<', $tmp);
        my $stdout = join("", <$fh>);
        close($fh);
        if ($stdout =~ m/DONE-/) {
            if ($stdout !~ m/DONE-0/) {
                die "ipmitool died: $stdout";
            }
            return $stdout;
        }
    }
    die "ipmitool did not finish";
}

sub restart_host {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    while (1) {
        my $stdout = $self->ipmitool('chassis power status');
        last if $stdout =~ m/is off/;
        $self->ipmitool('chassis power off');
        sleep(2);
    }

    $self->ipmitool("chassis power on");
    while (1) {
        my $ret = $self->ipmitool('chassis power status');
        last if $ret =~ m/is on/;
        $self->ipmitool('chassis power on');
        sleep(2);
    }
}

sub relogin_vnc {
    my ($self) = @_;

    if ($self->{vnc}) {
        close($self->{vnc}->socket);
        sleep(1);
    }

    $self->activate_console(
        {
            testapi_console => 'bootloader',
            backend_console => 'vnc-base',
            backend_args    => {
                hostname => $bmwqemu::vars{IPMI_HOSTNAME},
                port     => 5900,
                username => $bmwqemu::vars{IPMI_USER},
                password => $bmwqemu::vars{IPMI_PASSWORD},
                ikvm     => 1
            }});
    return 1;
}

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file;
    $self->activate_console({testapi_console => "worker", backend_console => "local-Xvnc"});
    my $console     = $self->{consoles}->{worker};
    my $display     = $console->{DISPLAY};
    my $window_name = 'IPMI';
    system("DISPLAY=$display xterm -title '$window_name' -e bash & echo \$!");
    sleep(1);
    my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
    chomp($window_id);
    $self->restart_host;
    $self->relogin_vnc;
    $self->start_serial_grab;
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    $self->stop_serial_grab();
    return {};
}

sub do_savevm {
    my ($self, $args) = @_;
    print "do_savevm ignored\n";
    return {};
}

sub do_loadvm {
    my ($self, $args) = @_;
    die "if you need loadvm, you're screwed with IPMI";
}

sub status {
    my ($self) = @_;
    print "status ignored\n";
    return;
}

# serial grab

sub start_serial_grab {
    my $self = shift;
    my $pid  = fork();
    if ($pid == 0) {
        setpgrp 0, 0;
        my @cmd = $self->ipmi_cmdline();
        push(@cmd, ('-I', 'lanplus', 'sol'));
        my @deactivate = @cmd;
        push(@deactivate, 'deactivate');
        push(@cmd,        'activate');
        my $ret;
        eval { $ret = system(@deactivate) };
        print "deactivate $ret\n";
        #unshift(@cmd, ("setsid", "-w"));
        print join(" ", @cmd);
        # FIXME use 'socat' for this?
        open(my $serial, '>',  $bmwqemu::serialfile) || die "can't open $bmwqemu::serialfile";
        open(STDOUT,     ">&", $serial)              || die "can't dup stdout: $!";
        open(STDERR,     ">&", $serial)              || die "can't dup stderr: $!";
        open(my $zero,   '<',  '/dev/zero');
        open(STDIN,      ">&", $zero);
        exec("script", "-efqc", "@cmd");
        die "exec failed $!";
    }
    else {
        $self->{serialpid} = $pid;
    }
    return;
}

sub stop_serial_grab {
    my $self = shift;
    return unless $self->{serialpid};
    kill("-TERM", $self->{serialpid});
    return waitpid($self->{serialpid}, 0);
}

# serial grab end

1;

# vim: set sw=4 et:
