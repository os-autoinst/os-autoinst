package distribution;
use strict;

use testapi ();

sub new() {
    my ($class) = @_;

    my $self = bless { class => $class };
    return $self, $class;
}

sub init() {
    # no cmds on default distri
}

sub x11_start_program($$$) {
    my ($program, $timeout, $options) = @_;
    $timeout ||= 6;
    $options ||= {};

    bmwqemu::mydie("TODO: implement x11 start for your distri " . testapi::get_var('DISTRI'));
}

sub ensure_installed {
    my ($self, @pkglist) = @_;

    if ( testapi::check_var( 'DISTRI', 'debian' ) ) {
        testapi::x11_start_program( "su -c 'aptitude -y install @pkglist'", 4, { terminal => 1 } );
    }
    elsif ( testapi::check_var( 'DISTRI', 'fedora' ) ) {
        testapi::x11_start_program( "su -c 'yum -y install @pkglist'", 4, { terminal => 1 } );
    }
    else {
        bmwqemu::mydie("TODO: implement package install for your distri " . testapi::get_var('DISTRI'));
    }
    if ($testapi::password) { testapi::type_password; testapi::send_key("ret", 1); }
    wait_still_screen( 7, 90 );    # wait for install
}

sub become_root() {
    my ($self) = @_;

    testapi::script_sudo( "bash", 0 );    # become root
    testapi::script_run("test $(id -u) -eq 0 && echo 'imroot' > /dev/$testapi::serialdev");
    testapi::wait_serial( "imroot", 5 ) || die "Root prompt not there";
    testapi::script_run("cd /tmp");
}

=head2 script_run

script_run($program, [$wait_seconds])

Run $program (by assuming the console prompt and typing it).
Wait for idle before  and after.

=cut

sub script_run($;$) {

    # start console application
    my ($self, $name, $wait) = @_;

    testapi::wait_idle();

    testapi::type_string "$name\n";
    testapi::wait_idle($wait);
}

=head2 script_sudo

script_sudo($program, $wait_seconds)

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds

=cut

sub script_sudo($$) {
    my ($self, $prog, $wait) = @_;

    testapi::type_string "sudo $prog\n";
    if ( testapi::check_screen "sudo-passwordprompt", 3 ) {
        testapi::type_password;
        testapi::send_key "ret";
    }
    testapi::wait_idle($wait);
}

1;
# vim: set sw=4 et:
