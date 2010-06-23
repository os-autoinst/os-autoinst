use strict;
use base "basetest";
use bmwqemu;

our %valueranges=(
	LVM=>[0,1], 
	USEIMAGES=>[0,1],
	DESKTOP=>[qw(kde gnome xfce lxde)],
);

sub setrandomenv()
{
	foreach my $k (keys %valueranges) {
		next if defined $ENV{$k};
		next if $k eq "DESKTOP" && $ENV{LIVECD};
		my @range=@{$valueranges{$k}};
		my $rand=int(rand(scalar @range));
		$ENV{$k}=$range[$rand];
		diag "randomenv $k=$ENV{$k}";
	}
}

sub run()
{
	setrandomenv if($ENV{RANDOMENV});
	$ENV{DESKTOP}||="kde";
}

