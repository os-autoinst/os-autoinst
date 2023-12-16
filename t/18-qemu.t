#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Fatal;
use Test::Warnings qw(warnings :report_warnings);
use Test::Output qw(stderr_from);
use Mojo::File qw(tempfile tempdir path);
use Carp 'cluck';
use Mojo::Util qw(scope_guard);
use Mojo::JSON 'decode_json';
use Test::MockModule;
use File::Copy qw(move);
use bmwqemu;

use OpenQA::Qemu::BlockDevConf;
use OpenQA::Qemu::Proc;

use constant TMPPATH => '/tmp/18-qemu.t/';

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir "$dir/testresults";

$SIG{__DIE__} = sub { cluck(shift); };

bmwqemu::init_logger;

my $bdc;
my @cmdl;
my @gcmdl;

@cmdl = ('-blockdev', 'driver=file,node-name=hd1-file,filename=raid/hd1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd1,file=hd1-file,cache.no-flush=on,discard=unmap',
    '-device', 'virtio-blk,id=hd1-device,drive=hd1');
$bdc = OpenQA::Qemu::BlockDevConf->new();
$bdc->add_new_drive('hd1', 'virtio-blk', '10G');
@gcmdl = $bdc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for single new drive');

@cmdl = [qw(create -f qcow2 raid/hd1 10G)];
@gcmdl = $bdc->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img command line for single new drive');

my $compress = 1;
@cmdl = (['convert', '-c', '-W', '-O', 'qcow2', 'raid/hd1', 'images/hd1.qcow2']);
@gcmdl = $bdc->gen_qemu_img_convert(qr/^hd/, 'images', 'hd1.qcow2', $compress);
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img convert for single new drive');

$compress = 0;
@cmdl = (['convert', '-O', 'qcow2', 'raid/hd1', 'images/hd1.qcow2']);
@gcmdl = $bdc->gen_qemu_img_convert(qr/^hd/, 'images', 'hd1.qcow2', $compress);
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img convert for single new drive, without compression');

my %vars;
my $proc;

%vars = (
    NUMDISKS => 1,
    HDDMODEL => 'virtio-blk',
    CDMODEL => 'virtio-cd',
    HDDSIZEGB_1 => 42,
    HDD_1 => "$Bin/data/test-image-disk.vmdk"
);
$proc = qemu_proc('-foo', \%vars);
@cmdl = ([qw(create -f qcow2 -F vmdk -b), "$Bin/data/test-image-disk.vmdk", qw(raid/hd0-overlay0 42G)]);
@gcmdl = $proc->blockdev_conf->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'qemu-img create call for a vmdk disk image');

@cmdl = ('-blockdev', 'driver=file,node-name=hd1-file,filename=raid/hd1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd1,file=hd1-file,cache.no-flush=on,discard=unmap',
    '-device', 'virtio-blk,id=hd1-device,drive=hd1',
    '-blockdev', 'driver=file,node-name=hd2-file,filename=raid/hd2,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd2,file=hd2-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-blk,id=hd2-device,drive=hd2');
$bdc = OpenQA::Qemu::BlockDevConf->new();
$bdc->add_new_drive('hd1', 'virtio-blk', '10G');
$bdc->add_new_drive('hd2', 'scsi-blk', '12G');
@gcmdl = $bdc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for multiple new drives');

@cmdl = qw(raid/hd1 raid/hd2);
@gcmdl = $bdc->gen_unlink_list();
is_deeply(\@cmdl, \@gcmdl, 'Generate unlink list for multiple new drives');

@cmdl = ([qw(create -f qcow2  raid/hd1 10G)],
    [qw(create -f qcow2  raid/hd2 12G)]);
@gcmdl = $bdc->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img command line for multiple new drives');

@cmdl = ('-blockdev', 'driver=file,node-name=hd1-overlay0-file,filename=raid/hd1-overlay0,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd1-overlay0,file=hd1-overlay0-file,cache.no-flush=on,discard=unmap',
    '-device', 'virtio-blk,id=hd1-device,drive=hd1-overlay0');
$bdc = OpenQA::Qemu::BlockDevConf->new();
$bdc->add_existing_drive('hd1', '/abs/path/sle15-minimal.qcow2', 'virtio-blk', 22548578304);
@gcmdl = $bdc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for single existing drive');

@cmdl = ([qw(create -f qcow2 -F qcow2 -b /abs/path/sle15-minimal.qcow2 raid/hd1-overlay0 22548578304)]);
@gcmdl = $bdc->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img command line for single existing drive');

@cmdl = qw(raid/hd1-overlay0);
@gcmdl = $bdc->gen_unlink_list();
is_deeply(\@cmdl, \@gcmdl, 'Generate unlink list for single existing drive');

$compress = 1;
@cmdl = (['convert', '-c', '-W', '-O', 'qcow2', 'raid/hd1-overlay0', 'images/hd1.qcow2']);
@gcmdl = $bdc->gen_qemu_img_convert(qr/^hd1/, 'images', 'hd1.qcow2', $compress);
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img convert for single existing drive');

@cmdl = ('qemu-kvm', '-foo',
    '-blockdev', 'driver=file,node-name=hd0-overlay0-file,filename=raid/hd0-overlay0,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0-overlay0,file=hd0-overlay0-file,cache.no-flush=on,discard=unmap',
    '-device', 'virtio-blk,id=hd0-device,drive=hd0-overlay0,bootindex=0,serial=hd0');
%vars = (NUMDISKS => 1,
    HDDMODEL => 'virtio-blk',
    CDMODEL => 'virtio-cd',
    HDDSIZEGB => 69,
    HDD_1 => "$Bin/data/Core-7.2.iso",
    UEFI => 1);
$proc = qemu_proc('-foo', \%vars);
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for single existing UEFI disk using vars');

@cmdl = ([qw(create -f qcow2 -F raw -b), "$Bin/data/Core-7.2.iso", qw(raid/hd0-overlay0 11116544)]);
@gcmdl = $proc->blockdev_conf->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img command line for single existing UEFI disk');

@cmdl = ('qemu-kvm', '-foo',
    '-device', 'virtio-scsi-device,id=scsi0',
    '-device', 'virtio-scsi-device,id=scsi1',

    '-blockdev', 'driver=file,node-name=hd0-file,filename=raid/hd0,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0,file=hd0-file,cache.no-flush=on,discard=unmap',
    '-device', 'sega-mega,id=hd0-device-path0,drive=hd0,share-rw=true,bus=scsi0.0,bootindex=0,serial=hd0',
    '-device', 'sega-mega,id=hd0-device-path1,drive=hd0,share-rw=true,bus=scsi1.0,serial=hd0',

    '-blockdev', 'driver=file,node-name=hd1-file,filename=raid/hd1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd1,file=hd1-file,cache.no-flush=on,discard=unmap',
    '-device', 'sega-mega,id=hd1-device-path0,drive=hd1,share-rw=true,bus=scsi0.0,serial=hd1',
    '-device', 'sega-mega,id=hd1-device-path1,drive=hd1,share-rw=true,bus=scsi1.0,serial=hd1');
%vars = (NUMDISKS => 2,
    HDDMODEL => 'sega-mega',
    CDMODEL => 'foo',
    HDDSIZEGB => 420,
    SCSICONTROLLER => 'virtio-scsi-device',
    MULTIPATH => 1,
    PATHCNT => 2);
$proc = qemu_proc('-foo', \%vars);

@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for new drives on multipath');

path(TMPPATH)->make_path();
my $path = TMPPATH . '/multipath.json';
path($path)->spew($proc->serialise_state());
$proc = OpenQA::Qemu::Proc->new()
  ->_static_params(['-foo'])
  ->qemu_bin('qemu-kvm');
$proc->deserialise_state(path($path)->slurp());
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Multipath Command line after serialisation and deserialisation');

$ENV{QEMU_IMG_CREATE_TRIES} = 2;
my $expected = qr/failed after 2 tries.*No such.*directory/s;
my @warnings = warnings {
    like exception { $proc->init_blockdev_images() }, $expected, 'init_blockdev_images can report error';
};
like $warnings[0], qr/No such.*directory/, 'failure message for no directory';
mkdir 'raid';
ok $proc->init_blockdev_images(), 'init_blockdev_images passes';

@cmdl = ('qemu-kvm', '-static-args',
    '-device', 'virtio-scsi-device,id=scsi0',

    '-blockdev', 'driver=file,node-name=hd0-file,filename=raid/hd0,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0,file=hd0-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-hd,id=hd0-device,drive=hd0,bootindex=0,serial=hd0',

    '-blockdev', 'driver=file,node-name=cd0-overlay0-file,filename=raid/cd0-overlay0,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=cd0-overlay0,file=cd0-overlay0-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-cd,id=cd0-device,drive=cd0-overlay0,serial=cd0');
%vars = (NUMDISKS => 1,
    HDDMODEL => 'scsi-hd',
    CDMODEL => 'scsi-cd',
    ISO => "$Bin/data/Core-7.2.iso",
    HDDSIZEGB => 10,
    SCSICONTROLLER => 'virtio-scsi-device');
$proc = qemu_proc('-static-args', \%vars);
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line for new drive and cdrom using vars');

path('/tmp/18-qemu.t/new-drive-and-cdrom.json')->spew($proc->serialise_state);

my $ssc;
my $ss;

@cmdl = ('qemu-kvm', '-static-args',
    '-device', 'virtio-scsi-device,id=scsi0',

    '-blockdev', 'driver=file,node-name=hd0-overlay1-file,filename=raid/hd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0-overlay1,file=hd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-hd,id=hd0-device,drive=hd0-overlay1,bootindex=0,serial=hd0',

    '-blockdev', 'driver=file,node-name=cd0-overlay1-file,filename=raid/cd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=cd0-overlay1,file=cd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-cd,id=cd0-device,drive=cd0-overlay1,serial=cd0',
    '-incoming', 'defer');
$ssc = $proc->snapshot_conf;
$ss = $ssc->add_snapshot('a snapshot');
$bdc = $proc->blockdev_conf;
$bdc->mark_all_created();
$bdc->for_each_drive(sub {
        $bdc->add_snapshot_to_drive(shift, $ss);
});
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line after snapshot');

$ss = $ssc->revert_to_snapshot('a snapshot');
is($ss->sequence, 1, 'Returned snapshot sequence number');
$bdc->for_each_drive(sub {
        my $drive = shift;
        $bdc->revert_to_snapshot($drive, $ss);
        is($drive->drive->needs_creating, 1, 'Active layer set to be recreated for drive ' . $drive->id);
});
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line after reverting a snapshot');

$path = TMPPATH . '/reverted-snapshot.json';
path($path)->spew($proc->serialise_state());
$proc = OpenQA::Qemu::Proc->new()
  ->_static_params(['-static-args'])
  ->qemu_bin('qemu-kvm')
  ->qemu_img_bin('qemu-img');
$proc->deserialise_state(path($path)->slurp());
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Command line after snapshot and serialisation')
  || diag(explain(\@gcmdl));

@cmdl = ([qw(create -f qcow2 -F qcow2 -b raid/hd0 raid/hd0-overlay1 10G)],
    [qw(create -f qcow2 -F qcow2 -b raid/cd0-overlay0 raid/cd0-overlay1 11116544)]);
@gcmdl = $bdc->gen_qemu_img_cmdlines();
is_deeply(\@gcmdl, \@cmdl, 'Generate reverted snapshot images');

@cmdl = qw(raid/hd0-overlay1 raid/cd0-overlay1);
@gcmdl = $bdc->gen_unlink_list();
is_deeply(\@gcmdl, \@cmdl, 'Generate unlink list of reverted snapshot images');

@cmdl = (['convert', '-c', '-W', '-O', 'qcow2', 'raid/hd0-overlay1', 'images/hd0.qcow2']);
@gcmdl = $bdc->gen_qemu_img_convert(qr/^hd0$/, 'images', 'hd0.qcow2', $compress);
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu-img convert with snapshots');

@cmdl = ('qemu-kvm', '-static-args',
    '-device', 'virtio-scsi-device,id=scsi0',

    '-blockdev', 'driver=file,node-name=hd0-overlay1-file,filename=raid/hd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0-overlay1,file=hd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-hd,id=hd0-device,drive=hd0-overlay1,bootindex=0,serial=hd0',

    '-blockdev', 'driver=file,node-name=cd0-overlay1-file,filename=raid/cd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=cd0-overlay1,file=cd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-cd,id=cd0-device,drive=cd0-overlay1,serial=cd0',
    '-incoming', 'defer');
$proc = qemu_proc('-static-args', \%vars);
$ssc = $proc->snapshot_conf;
$bdc = $proc->blockdev_conf;

for my $i (1 .. 10) {
    $ss = $ssc->add_snapshot("snapshot $i");
    $bdc->for_each_drive(sub {
            $bdc->add_snapshot_to_drive(shift, $ss);
    });
}
$bdc->mark_all_created();

$path = TMPPATH . '/many-snapshots.json';
path($path)->spew($proc->serialise_state());
$proc = OpenQA::Qemu::Proc->new()
  ->_static_params(['-static-args'])
  ->qemu_bin('qemu-kvm');
$proc->deserialise_state(path($path)->slurp());
$ssc = $proc->snapshot_conf;
$bdc = $proc->blockdev_conf;

$ss = $ssc->revert_to_snapshot('snapshot 1');
is($ss->sequence, 1, 'Returned snapshot sequence number');
$bdc->for_each_drive(sub {
        my $drive = shift;
        my $unlinks = $bdc->revert_to_snapshot($drive, $ss);
        is(scalar(@$unlinks), 9, 'Correct number of overlay files need unlinking for ' . $drive->id);
});
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line after deserialising and reverting a snapshot')
  || diag(explain(\@gcmdl));

%vars = (NUMDISKS => 1,
    HDDMODEL => 'scsi-hd',
    CDMODEL => 'scsi-cd',
    ISO => "$Bin/data/Core-7.2.iso",
    HDDSIZEGB => 10,
    SCSICONTROLLER => 'virtio-scsi-device',
    UEFI => 1,
    UEFI_PFLASH_CODE => "$Bin/data/uefi-code.bin",
    UEFI_PFLASH_VARS => "$Bin/data/uefi-vars.bin");
@cmdl = ('qemu-kvm', '-static-args',
    '-device', 'virtio-scsi-device,id=scsi0',

    '-blockdev', 'driver=file,node-name=hd0-overlay1-file,filename=raid/hd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=hd0-overlay1,file=hd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-hd,id=hd0-device,drive=hd0-overlay1,bootindex=0,serial=hd0',

    '-blockdev', 'driver=file,node-name=cd0-overlay1-file,filename=raid/cd0-overlay1,cache.no-flush=on',
    '-blockdev', 'driver=qcow2,node-name=cd0-overlay1,file=cd0-overlay1-file,cache.no-flush=on,discard=unmap',
    '-device', 'scsi-cd,id=cd0-device,drive=cd0-overlay1,serial=cd0',

    '-drive', 'id=pflash-code-overlay1,if=pflash,file=raid/pflash-code-overlay1',
    '-drive', 'id=pflash-vars-overlay1,if=pflash,file=raid/pflash-vars-overlay1',

    '-incoming', 'defer');
$proc = qemu_proc('-static-args', \%vars);
$ssc = $proc->snapshot_conf;
$bdc = $proc->blockdev_conf;

for my $i (1 .. 11) {
    $ss = $ssc->add_snapshot("snapshot $i");
    $bdc->for_each_drive(sub {
            $bdc->add_snapshot_to_drive(shift, $ss);
    });
}
$bdc->mark_all_created();

$path = TMPPATH . '/many-snapshots-pflash.json';
path($path)->spew($proc->serialise_state());
$proc = OpenQA::Qemu::Proc->new()
  ->_static_params(['-static-args'])
  ->qemu_bin('qemu-kvm');
$proc->deserialise_state(path($path)->slurp());
$ssc = $proc->snapshot_conf;
$bdc = $proc->blockdev_conf;

$ss = $ssc->revert_to_snapshot('snapshot 1');
is($ss->sequence, 1, 'Returned snapshot sequence number');
$bdc->for_each_drive(sub {
        my $drive = shift;
        my $unlinks = $bdc->revert_to_snapshot($drive, $ss);
        is(scalar(@$unlinks), 10, 'Correct number of overlay files need unlinking for ' . $drive->id);
});
@gcmdl = $proc->gen_cmdline();
is_deeply(\@gcmdl, \@cmdl, 'Generate qemu command line after deserialising and reverting a snapshot')
  || diag(explain(\@gcmdl));


sub qemu_proc ($static_params, $vars) {
    return OpenQA::Qemu::Proc->new()
      ->_static_params([$static_params])
      ->qemu_bin('qemu-kvm')
      ->qemu_img_bin('qemu-img')
      ->configure_controllers($vars)
      ->configure_blockdevs('disk', 'raid', $vars)
      ->configure_pflash(\%vars);
}

subtest 'non-existing-iso' => sub {
    $vars{ISO} .= 'XXX';
    my $err;
    my @warnings = warnings {
        eval {
            $proc = qemu_proc('-static-args', \%vars);
        };
        $err = $@;
    };
    my $expected = qr{qemu-img: Could not open.*data/Core-7.2.isoXXX.*No such file};
    like $err, $expected, 'Got expected eval error';
    is @warnings, 1, 'only a single-line failure message';
    like $warnings[0], $expected, 'Got expected warning';
    unlike $warnings[0], qr{malformed JSON}, 'No confusing JSON parsing error';
};

subtest DriveDevice => sub {

    use OpenQA::Qemu::DriveDevice;
    my $drive = OpenQA::Qemu::DriveDevice->new(id => 'test', last_overlay_id => 2);
    is $drive->new_overlay_id, 3, 'new_overlay_id() bumps last_overlay_id value';
    is($drive->_gen_node_name(3, 2), 'test-device-2', 'Expected generated node name matches');
    is($drive->_gen_node_name(1, 2), 'test-device', 'Expected generated node name matches');

};

subtest 'relative assets' => sub {
    $vars{$_} = "Core-7.2.iso" for qw(ISO ISO_1 UEFI_PFLASH_VARS);
    $vars{$_} = "some.qcow2" for qw(HDD_1 UEFI_PFLASH_VARS);
    symlink("$Bin/data/Core-7.2.iso", "./Core-7.2.iso");
    path('./some.qcow2')->spew('123');
    $proc = qemu_proc('-foo', \%vars);
    my @gcmdl = $proc->blockdev_conf->gen_qemu_img_cmdlines();
    @cmdl = (
        [qw(create -f qcow2 -F qcow2 -b), "$dir/some.qcow2", "raid/hd0-overlay0", 512],
        [qw(create -f qcow2 -F raw -b), "$dir/Core-7.2.iso", "raid/cd0-overlay0", 11116544],
        [qw(create -f qcow2 -F raw -b), "$dir/Core-7.2.iso", "raid/cd1-overlay0", 11116544],
        [qw(create -f qcow2 -F raw -b), "$Bin/data/uefi-code.bin", "raid/pflash-code-overlay0", 1966080],
        [qw(create -f qcow2 -F qcow2 -b), "$dir/some.qcow2", "raid/pflash-vars-overlay0", 512],
    );
    is_deeply(\@gcmdl, \@cmdl, 'find the asset real path') or diag explain \@gcmdl;
};

subtest 'qemu was killed due to the system being out of memory' => sub {
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    $mock_proc->redefine(check_qemu_oom => sub { return 0; });
    $proc = qemu_proc('-foo', \%vars);
    $proc->exec_qemu;
    $proc->_process->sleeptime_during_kill(0.1)->wait_stop;
    my $base_state = path(bmwqemu::STATE_FILE);
    ok -f $base_state, qq{state file "$base_state" exists};
    my $state = decode_json($base_state->slurp);
    is($state->{msg}, 'QEMU was killed due to the system being out of memory', 'qemu was killed and the reason was shown correctly');
    unlink("./Core-7.2.iso");
};

subtest 'qemu is not called on an empty file when ISO_1 is an empty string' => sub {
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    my $call_count = 0;
    $mock_proc->redefine(get_img_size => sub {
            my ($iso) = @_;    # uncoverable statement
            $call_count++;    # uncoverable statement
            die 'get_img_size called on an empty string' unless $iso;    # uncoverable statement
    });

    my %empty_iso_vars = (ISO_1 => '', NUMDISKS => 0);

    OpenQA::Qemu::Proc->new()->configure_blockdevs('disk', 'raid', \%empty_iso_vars);
    is($call_count, 0, 'get_img_size call count check');
};

subtest configure_controllers => sub {
    my $cc = Test::MockModule->new('OpenQA::Qemu::ControllerConf');
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my %vars = (HDDMODEL => 'virtio-scsi-foo');
    my $exception = exception { $proc->configure_controllers(\%vars) };
    like $exception, qr{Set HDDMODEL to scsi-hd and SCSICONTROLLER to virtio-scsi-foo}, 'correct exception for HDDMODEL';
    %vars = (HDDMODEL => '', CDMODEL => 'virtio-scsi-foo');
    $exception = exception { $proc->configure_controllers(\%vars) };
    like $exception, qr{Set CDMODEL to scsi-cd and SCSICONTROLLER to virtio-scsi-foo}, 'correct exception for CDMODEL';

    my @controllers;
    $cc->redefine(add_controller => sub ($self, $x, $y) {
            push @controllers, [$x, $y];
    });
    %vars = (HDDMODEL => '', CDMODEL => '', ATACONTROLLER => 'foo');
    $proc->configure_controllers(\%vars);
    is_deeply \@controllers, [[qw(foo ahci0)]], 'ATACONTROLLER added';
    @controllers = ();

    %vars = (HDDMODEL => '', CDMODEL => '', USBBOOT => 'foo');
    $proc->configure_controllers(\%vars);
    is_deeply \@controllers, [[qw(qemu-xhci xhci0)]], 'USBBOOT added';
};

subtest 'configure_blockdevs xz' => sub {
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    my %vars = (NUMDISKS => 1, HDD_1 => 'foo.xz', HDDMODEL => 'model');
    path('foo.xz')->spew('123');
    $mock_proc->redefine(runcmd => sub (@args) {
            move 'foo.xz', 'foo';
    });
    $mock_proc->redefine(which => sub (@) { 1 });
    my @size;
    $mock_proc->redefine(get_img_size => sub ($self, $file) {
            push @size, [$file, -s $file];
            return -s $file;
    });
    $proc->configure_blockdevs(disk => raid => \%vars);
    is_deeply \@size, [["$dir/foo", 3]], 'runcmd unxz called successfully';
};

subtest 'configure_blockdevs USBBOOT' => sub {
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    my $bdc = Test::MockModule->new('OpenQA::Qemu::BlockDevConf');
    my %vars = (NUMDISKS => 1, HDD_1 => 'foo', HDDMODEL => 'model', USBBOOT => 1, ISO => "$Bin/data/Core-7.2.iso", USBSIZEGB => '42');
    my @size;
    $mock_proc->redefine(get_img_size => sub ($self, $file) {
            push @size, [$file, -s $file];
            return -s $file;
    });
    my @iso;
    $bdc->redefine(add_iso_drive => sub ($self, $id, $file_name, $model, $size) {
            push @iso, [$id, $file_name, $model, $size];
    });
    $proc->configure_blockdevs(disk => raid => \%vars);
    is_deeply \@iso, [[usbstick => "$Bin/data/Core-7.2.iso" => 'usb-storage' => '42G']], 'add_iso_drive correctly called';
};

subtest 'configure_blockdevs boot from cdrom' => sub {
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my $dd = Test::MockModule->new('OpenQA::Qemu::DriveDevice');
    my %vars = (NUMDISKS => 0, HDD_1 => 'foo', CDMODEL => 'model', ISO_1 => "$Bin/data/Core-7.2.iso");
    my $index;
    $dd->redefine(bootindex => sub ($self, $ix) { $index = $ix });
    $proc->configure_blockdevs(cdrom => raid => \%vars);
    is $index, 0, 'bootindex correctly called';
};

subtest configure_pflash => sub {
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    my %vars = (UEFI => 1, UEFI_PFLASH => 1, UEFI_PFLASH_CODE => 'x');
    my $exc = exception { $proc->configure_pflash(\%vars) };
    like $exc, qr{Mixing old and new PFLASH variables}, 'Fatal mixing of old and new PFLASH';

    my $bdc = Test::MockModule->new('OpenQA::Qemu::BlockDevConf');
    my @flash;
    $bdc->redefine(add_pflash_drive => sub ($self, $id, $file_name, $size) {
            push @flash, [$id, $file_name, $size];
    });
    my @size;
    $mock_proc->redefine(get_img_size => sub ($self, $file) {
            push @size, [$file, -s $file];
            return -s $file;
    });
    %vars = (UEFI => 1, UEFI_PFLASH => 1, BIOS => 'foo');
    my $res = $proc->configure_pflash(\%vars);
    is_deeply \@flash, [[qw(pflash foo 3)]], 'add_pflash_drive correctly called';

    %vars = (UEFI => 1, UEFI_PFLASH_VARS => 'vars');
    $exc = exception { $proc->configure_pflash(\%vars) };
    like $exc, qr{Need UEFI_PFLASH_CODE with UEFI_PFLASH_VARS}, 'Fatal UEFI_PFLASH_VARS without UEFI_PFLASH_CODE';
};

subtest connect_qmp => sub {
    local $SIG{__DIE__} = undef;
    local $ENV{QEMU_QMP_CONNECT_ATTEMPTS} = -1;
    my $proc = OpenQA::Qemu::Proc->new;
    my $exc = exception { $proc->connect_qmp };
    like $exc, qr{Can't open QMP socket}, 'Fatal connect_qmp';
};

subtest save_state => sub {
    my $proc = OpenQA::Qemu::Proc->new;
    my $mock_proc = Test::MockModule->new('OpenQA::Qemu::Proc');
    $mock_proc->redefine(has_state => 0);
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my @info;
    $mock_bmwqemu->redefine(fctinfo => sub ($msg) { push @info, $msg });
    my $stderr = stderr_from { $proc->save_state };
    is $info[0], 'Refusing to save an empty state file to avoid overwriting a useful one', 'Info about not writing empty state fle';
    pass;
};

subtest revert_to_snapshot => sub {
    local $SIG{__DIE__} = undef;
    my $proc = OpenQA::Qemu::Proc->new;
    my $mock_sc = Test::MockModule->new('OpenQA::Qemu::SnapshotConf');
    my $scname;
    $mock_sc->redefine(revert_to_snapshot => sub ($self, $name) { $scname = $name });
    my $bdc = Test::MockModule->new('OpenQA::Qemu::BlockDevConf');
    my $drive = OpenQA::Qemu::DriveDevice->new(id => 'foo');
    my $bdcname;
    $bdc->redefine(revert_to_snapshot => sub ($, $name, $sn) {
            $bdcname = $sn;
            return ['foo'];
    });
    $bdc->redefine(for_each_drive => sub ($self, $cb) {
            $cb->($drive);
    });
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my @diag;
    $mock_bmwqemu->redefine(diag => sub ($msg) { push @diag, $msg });

    path('foo')->spew('123');
    $proc->revert_to_snapshot('foo');
    is $scname, 'foo', 'SnapshotConf->revert_to_snapshot called';
    is $bdcname, 'foo', 'BlockDevConf->revert_to_snapshot called';
    is -e 'foo', undef, 'foo was removed';
    is $diag[0], 'Unlinking foo', 'Message about unlinking foo';
};

done_testing();
