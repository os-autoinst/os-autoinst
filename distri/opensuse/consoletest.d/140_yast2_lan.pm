use base "basetest";
use bmwqemu;
# test yast2 lan functionality
# https://bugzilla.novell.com/show_bug.cgi?id=600576


sub run()
{ 
  my $self=shift;
  script_sudo("/sbin/yast2 lan");
  waitstillimage();
  
  if($ENV{LIVETEST} || $ENV{DISTRI} eq "sled-11" || $ENV{LAPTOP}) {
    sendkey "ret";   # confirm networkmanager popup
    sleep 1;
    sendkey "alt-t"; # traditional ifup
    sleep 1;
  }
  
  my $hostname="susetest";
  my $domain="zq1.de";
  
  sendkey("alt-s"); # open hostname tab
  sleep 2;
  sendkey("tab");
  for(1..15){sendkey("backspace")}
  sendautotype($hostname);
  sendkey("tab");
  for(1..15){sendkey("backspace")}
  sendautotype($domain);
  sleep 5;
  $self->check_screen;
  sendkey("alt-o"); # confirm possible network manager warning
  sendkey("alt-o"); # OK=>Save&Exit
  sleep 20;
  waitidle();
  waitidle(180);
  
  sendkey("ret");
  sendkey("ctrl-l"); # clear screen
  script_run('echo $?');
  script_run('hostname');
  $self->check_screen;
}

sub test_flags() {
  return { 'milestone' => 1 };
}

1;

