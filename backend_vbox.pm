#!/usr/bin/perl -w
package backend_vbox;
use strict;

our $vmname="osautoinst";

sub vbox_controlvm
{
	system(qw"VBoxManage controlvm", $vmname, @_);
}

# keymap relates to qemu/monitor.c
my @keymap=split(/ /,"? esc 1 2 3 4 5 6 7 8 9 0 minus equal backspace tab q w e r t y u i o p bracket_left bracket_right ret ctrl a s d f g h j k l semicolon apostrophe grave_accent shift backslash z x c v b n m comma dot slash shift_r asterisk alt spc caps_lock f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 num_lock scroll_lock kp_7 kp_8 kp_9 kp_subtract kp_4 kp_5 kp_6 kp_add kp_1 kp_2 kp_3 kp_0 kp_decimal sysrq ? < f11 f12");
my %keymap=();
my %keymaprev=(
0x9d, "ctrl_r",
0xb7, "print",
0xb8, "alt_r",
0xc7, "home",
0xc9, "pgup",
0xd1, "pgdn",
0xcf, "end",
0xcb, "left",
0xc8, "up",
0xd0, "down",
0xcd, "right",
0xd2, "insert",
0xd3, "delete",
0xdd, "menu",
);
{
	my $n=0;
	foreach my $k (@keymap) {$keymap{$k}=$n++;}
	foreach my $k (keys %keymaprev) {$keymap{$keymaprev{$k}}=$k}
}

sub sendkey($)
{
	my $self=shift;
	my $key=shift;
	my @codes=();
	foreach my $part (reverse split("-", $key)) {
		my $keycode=$keymap{$part};
		if(!$keycode) {print "unknown key $part\n"}
		my $keycodeup=sprintf("%02x", $keycode^0x80);
		$keycode=sprintf("%02x", $keycode);
		unshift(@codes, $keycode);
		push(@codes, $keycodeup);
	}
	print STDOUT "sendkey($key) => @codes\n";
	vbox_controlvm("keyboardputscancode", @codes);
}

sub screendump($)
{
	my $self=shift;
	my $filename=shift;
	my $r=int(rand(1e9));
	my $tmp="/tmp/vbox-$r.png";
	vbox_controlvm("screenshotpng", $tmp);
	system("convert", $tmp, $filename);
	unlink $tmp;
}

sub system_reset() { vbox_controlvm("reset"); }
sub system_powerdown() { vbox_controlvm("acpipowerbutton"); }
sub quit() { vbox_controlvm("poweroff"); }
sub mouse_move($)
{
	warn "TODO: mouse_move"; # not too bad because cursor does not appear on screenshots
}
sub eject($)
{
	system(qq'VBoxManage storageattach $vmname --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium emptydrive');
}
sub mouse_button($) {warn "TODO: mouse_button @_"}
sub wavcapture($) {
	my $self=shift;
	my $wavfilename=shift;
	system("$bmwqemu::scriptdir/tools/pawav.pl $wavfilename &");
}

sub stopcapture($) {
	system("killall", "parec");
}

sub send($)
{
	my $self=shift;
	my $line=shift;
	print STDOUT "send($line)\n";
	$line=~s/^(\w+)\s*//;
	my $cmd=$1;
	if($cmd) {
		$self->$cmd($line);
	} else {
		warn "unknown cmd in $line";
	}
}

sub open_management()
{
}

sub start_vm
{
	my $self=shift;
	# TODO: assemble VM with ISO and disks similar to startqemu.pm
	# attach iso as DVD:
	system("VBoxManage", "storageattach", $self->{vmname}, "--storagectl", "IDE Controller", qw"--port 1 --device 0 --type dvddrive --medium", $ENV{ISO});
	# pipe serial console output to file:
	system("VBoxManage", "modifyvm", $self->{vmname}, "--uartmode1", "file", "serial0");
	system("VBoxManage", "modifyvm", $self->{vmname}, "--uart1", "0x3f8", 4);
	system(qw"VBoxManage startvm", $self->{vmname});
	my $pid=`pidof VirtualBox`; chomp($pid);
	$pid=~s/ .*//; # use first pid, in case GUI was open
	$bmwqemu::qemupid=$pid;
#	return 1;
	return(($?>>8)==0);
}

sub new()
{
	my $class=shift;
	my $self={class=>$class, vmname=>$vmname};
	$self=bless $self, $class;
	return $self;
}

1;
