package backend::pvm;
use strict;
use base ('backend::baseclass');
use bmwqemu qw(fileContent diag save_vars);
require IPC::System::Simple;
use autodie qw(:all);
use File::Basename;
use Digest::MD5 qw(md5_hex);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;

    $self->{pid}         = undef;
    $self->{children}    = [];
    $self->{pidfilename} = 'pvm.pid';
    $self->{pvmctl}      = '/usr/bin/pvmctl';
    die "pvmctl not found" unless -x $self->{pvmctl};

    return $self;
}

sub do_start_vm {
    my $self = shift;
    $self->unlink_crash_file;
    $self->start_lpar();
    return {};
}

sub runcmd {
    diag "running " . join(' ', @_);
    return system(@_);
}

sub pvmctl {
    my $self = shift @_;
    my $vars = \%bmwqemu::vars;
    my ($type, $action) = @_;
    push(my @cmd, $self->{pvmctl}, $type, $action);
    my $lpar = $vars->{LPAR};

    if ($type =~ /lpar/) {
        push(@cmd, "-i", "name=" . $lpar) if ($action =~ /power|restart|delete/);
        if ($action =~ /create/) {
            my ($type, $action, $cpu, $memory) = @_;
            push(@cmd, qw{--proc-type shared --sharing-mode uncapped --type AIX/Linux});
            push(@cmd, "--proc", $cpu, "--mem", $memory, "--name", $lpar);
            push(@cmd, "--proc-unit", $cpu * 0.05);
        }
    }
    elsif ($type =~ /scsi/) {
        my ($type, $action, $kind, $file) = @_;
        push(@cmd, "--type", $kind, "--stor-id", $file);
        push(@cmd, "--lpar", "name=" . $lpar);
        push(@cmd, "--vg", "name=rootvg") if ($type =~ /lv/);
    }
    elsif ($type =~ /lv/) {
        my ($type, $action, $name, $size) = @_;
        push(@cmd, "--name", $name, "--size", $size);
    }
    elsif ($type =~ /eth/) {
        my ($type, $action, $vlan, $vswitch) = @_;
        push(@cmd, "--pvid", $vlan, "--vswitch", $vswitch, "-p", "name=" . $lpar);
    }
    else {
        die "Unrecognized command $type";
    }
    runcmd(@cmd);
}
sub attach_console {
    my $vars    = \%bmwqemu::vars;
    my $vncport = qx{sudo /usr/sbin/mkvtermutil --id $vars->{LPARID} --vnc --local --log serial0 2>/dev/null};
    $vncport =~ /([0-9]+)/;
    chomp($vncport);
    $vars->{VNC} = $vncport;
    diag "VNC is $vars->{VNC}";
}

sub image_exists {
    my ($img, $size) = @_;
    #lv already exists?
    my @cmd;
    my $pvmctlcmd = "pvmctl lv list -w LogicalVolume.name=$img -d LogicalVolume.name LogicalVolume.capacity -f , --hide-label";
    my ($name, $capacity) = split(",", qx/$pvmctlcmd/);
    return 1 if !($name =~ /$img/);
    if (($img =~ /$name/) && ($size =~ /$capacity/)) {
        push(@cmd, "sudo viosvrcmd --id 1 -r -c \"dd if=/dev/zero bs=1024 count=1 of=/dev/r$name\"");
    }
    else {
        push(@cmd, "sudo viosvrcmd --id 1 -c\"rmbdsp -sp rootvg -bd $name\"");
    }
    runcmd(@cmd);
}
sub start_lpar {
    my $self = shift;
    my $vars = \%bmwqemu::vars;
    #general settiings
    $vars->{LPAR} = "osauto" . $vars->{WORKER_ID};
    $vars->{CPUS} ||= 1;
    $vars->{MEM}  ||= "2048";
    #disk settings
    $vars->{NUMDISKS}  ||= 1;
    $vars->{HDDSIZEGB} ||= 15;
    #network settings
    $vars->{NIC}     ||= "sea";
    $vars->{NICVLAN} ||= 1;
    $vars->{VSWITCH} ||= "ETHERNET0";
    #unfortunately NovaLink can't take files longer than 38 chars. So we need to shorten ISO name here
    $vars->{VIOISO} = md5_hex(basename($vars->{ISO})) . ".iso";
    my $iso = $vars->{VIOISO};
    die "$iso exceeds 37 characters\n" if (length($iso) > 37);

    if (!($vars->{ARCH} =~ /ppc64/)) {
        die "arch $vars->{ARCH} is not allowed on pvm backend";
    }
    #create lpar
    $self->pvmctl("lpar", "create", $vars->{CPUS}, $vars->{MEM});

    my $id = substr(qx/pvmctl lpar list -d LogicalPartition.id --where LogicalPartition.name=$vars->{LPAR}/, 3);
    chomp($id);
    $vars->{LPARID} = $id;
    bmwqemu::save_vars();

    #we copy isos from nfs mount on VIO side to VMLibrary
    my $source_iso = '/iso/' . basename($vars->{ISO});
    diag "source_iso: $source_iso, vio iso: $iso";
    my $iso_present = qx/pvmctl media list -d VirtualOpticalMedia.media_name --where VirtualOpticalMedia.name=$iso/;
    if ($iso_present !~ /$iso/) {
        #copy over from nfs to VMLibrary
        my @viocmd = ("sudo viosvrcmd --id 1 -r -c\"cp $source_iso /var/vio/VMLibrary/$iso\"");
        push(@viocmd, "sudo viosvrcmd --id 1 -r -c\"chown padmin:staff /var/vio/VMLibrary/$iso\"");
        push(@viocmd, "sudo viosvrcmd --id 1 -c\"chvopt -name $iso -access ro\"");
        foreach my $viocmd (@viocmd) {
            runcmd($viocmd);
        }
    }
    $self->pvmctl('scsi', 'create', 'vopt', $iso);

    for my $i (1 .. $vars->{NUMDISKS}) {
        my $name = $vars->{LPAR} . "_" . $i;
        my $size = $vars->{HDDSIZEGB};
        $self->pvmctl("lv", "create", $name, $size) if !image_exists($name, $size);
        $self->pvmctl("scsi", "create", "lv", $name);
    }

    $self->pvmctl("eth", "create", $vars->{NICVLAN}, $vars->{VSWITCH});
    $self->pvmctl("lpar", "power-on");

    attach_console;

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => 'localhost',
            port     => $vars->{VNC}});
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});
}

sub do_stop_vm {
    my $self  = shift;
    my $vars  = \%bmwqemu::vars;
    my $state = qx{pvmctl lpar list -i id=$vars->{LPARID} -d LogicalPartition.state --hide-label};
    $self->pvmctl("lpar", "power-off") if ($state =~ /running/);
    runcmd("rmvterm", "--id", $vars->{LPARID});
    for my $i (1 .. $vars->{NUMDISKS}) {
        my $disk = $vars->{LPAR} . "_" . $i;
        $self->pvmctl("scsi", "delete", "lv", $disk);
    }
    $self->pvmctl("scsi", "delete", "vopt", $vars->{VIOISO});
    $self->pvmctl("lpar", "delete");
}
