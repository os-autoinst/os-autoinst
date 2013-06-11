use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
  return $ENV{MEDIACHECK};
}

sub run
{
  my $self=shift;
  waitforneedle("mediacheck-ok", 300);
  sendkey "ret";
}

sub test_flags() {
        return {'fatal' => 1};
}

1;
