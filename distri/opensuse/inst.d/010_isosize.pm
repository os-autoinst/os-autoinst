use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{ISO_MAXSIZE};
}

sub run
{
	my $self = shift;
	my $iso = $ENV{ISO};
	my $size = -s $iso;
	diag("iso_size=$size");
	my $result = 'ok';
	if( $size > $ENV{ISO_MAXSIZE}) {
		$result = 'fail';
	}
	$self->result($result);
}

sub test_flags() {
        return {'important' => 1};
}

1;
