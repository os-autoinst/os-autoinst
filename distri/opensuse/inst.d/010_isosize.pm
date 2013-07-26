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
	my $result = 'ok';
	my $max = $ENV{ISO_MAXSIZE};
	if( $size > $max) {
		$result = 'fail';
	}
	diag("check if actual iso size $size fits $max: $result");
	$self->result($result);
}

sub test_flags() {
        return {'important' => 1};
}

1;
