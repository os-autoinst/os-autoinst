use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
if($ENV{ISO}=~m/i586/) {
	script_sudo("zypper ref; echo zypper_ref_finished > /dev/$serialdev");
	waitserial('zypper_ref_finished');
	script_run("clear");
	script_run("uname -m");
	$my_script = "echo 'Checking i686 glibc...';\\\n";
	$my_script.= 'if [ "`uname -m | grep i686`" ]; then' . "\\\n";
	$my_script.= '   if [ "`rpm -q glibc    | grep i686`" ]  &&  [ "`zypper se -s glibc | grep i686`" ]; then' . "\\\n";
	$my_script.= '      echo "Looks ok"' . ";\\\n";
	$my_script.= "   else \\\n";
	$my_script.= '      echo "rpm""' . ";\\\n";
	$my_script.= "      rpm -q glibc       | grep i686;\\\n";
	$my_script.= '      echo "zypper""' . ";\\\n";
	$my_script.= "      zypper se -s glibc | grep i686;\\\n";
	$my_script.= "   fi; \\\n";
	$my_script.= "else \\\n";
	$my_script.= '   [ -z "`zypper se -s glibc | grep i686`" ]  || echo "Looks ok"' . ";\\\n";
	$my_script.= "fi; \\\n echo glibc_finished > /dev/$serialdev";
	script_run($my_script);
	waitserial('glibc_finished');
	$self->check_screen;
}
}

1;
