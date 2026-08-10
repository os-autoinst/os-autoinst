# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Qemu::HWProfiles;
use Mojo::Base -signatures;
use Mojo::File qw(path);
use YAML::PP;

my $serial = [
    ['chardev', 'ringbuf,id=serial0,logfile=serial0,logappend=on'],
    ['serial', 'chardev:serial0'],
];

our %profiles = (
    default => {
        default => $serial,
        provides => [qw(serial)],
    },
);

my $external_profiles;

sub get_profile ($name, $arch) {
    if (!$profiles{$name}) {
        $external_profiles //= YAML::PP->new->load_file(path(__FILE__)->sibling('hw_profiles.yaml'));
        return undef unless $external_profiles->{$name};
        my $p = $external_profiles->{$name};
        return {args => ($p->{$arch} // $p->{default} // []), provides => ($p->{provides} // [])};
    }
    my $p = $profiles{$name};
    return {args => ($p->{$arch} // $p->{default} // []), provides => ($p->{provides} // [])};
}

1;
