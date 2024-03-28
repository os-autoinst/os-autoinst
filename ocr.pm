# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=encoding utf8

=head1 OCR Package

Providing optical character recognition (OCR) functionality

=cut

package ocr;
use Mojo::Base -strict, -signatures;
require IPC::System::Simple;
use autodie ':all';
use File::Temp 'tempdir';
use File::Which;
use Scalar::Util 'blessed';
use Exporter 'import';
use bmwqemu 'fctwarn';

our @EXPORT = qw(img_to_str ocr_installed);
our $MAX_PIX_HORIZONTAL = 1024;
our $MAX_PIX_VERTICAL = 768;
our $OCR_INSTALLED = which('gocr');

=head2 img_to_str

Reduces the information carried by the provided image to a character string.
Probably the underlying implementation used by this function is not complete
and might lead to wrong or incomplete results in some cases.

=head3 Params

=over

=item *

img - A tinycv image

=back

=head3 returns

Character string of characters '-_.:,;()[]{}<>0-9a-zA-Z~+*^@#$%&/=?!§',
where '§' is placed for each unrecognized character. Implicitly, '§'
itself can't be recognized. Keep that in mind for comparison!
Returns undef on failure.

=cut

sub img_to_str ($img) {
    # uncoverable branch true
    return undef unless $OCR_INSTALLED;

    if (!blessed($img) || !$img->isa('tinycv::Image')) {
        fctwarn('Not a reference to object with type tinycv::Image (internal error, probably a bug)!');
        return undef;
    }

    # Better be safe than sorry. C.f. CVE-2005-1141
    unless ($img->xres() <= $MAX_PIX_HORIZONTAL && $img->yres() <= $MAX_PIX_VERTICAL) {
        fctwarn("Skipping OCR evaluation of image, resolution too high (max: " .
              "$MAX_PIX_HORIZONTAL x $MAX_PIX_VERTICAL)");
        return undef;
    }

    my $ret = '';
    my $tmpdir = tempdir(CLEANUP => 1);
    my $img_fpath = $tmpdir . 'ocrimg.png';
    my $stderr_fpath = $tmpdir . 'stderr.txt';

    unless ($img->write($img_fpath)) {
        fctwarn('Writing image to prepare for OCR failed!');
        return undef;
    }

    chomp($ret = `gocr -C '--_.:,;()[]{}<>0-9a-zA-Z~+*^@#\$\%&/=?!' -u '§' $img_fpath 2> $stderr_fpath`);
    utf8::decode($ret);

    if ($?) {
        my $exit_code = $? >> 8;
        fctwarn("The OCR program exited with error $exit_code!");

        my $stderr_fh;
        # uncoverable branch true Can't mock CORE::GLOBAL during runtime.
        unless (open($stderr_fh, '<:utf8', $stderr_fpath)) {
            # uncoverable statement Branch not coverable.
            fctwarn('STDERR of OCR program could not be read!');
            # uncoverable statement Branch not coverable.
            return undef;
        }
        my @stderr_lines = <$stderr_fh>;
        foreach my $line (@stderr_lines) {
            fctwarn($line);
        }
        # uncoverable branch true Can't mock CORE::GLOBAL during runtime.
        unless (close($stderr_fh)) {
            # uncoverable statement Branch not coverable.
            fctwarn('Could not close filehandle of OCR program error log.');
        }
        return undef;
    }
    return $ret;
}

=head2 ocr_installed

Checks if the OCR program is installed.

=head3 returns

=over

 * b in {0, 1} | 0 if the OCR program is not installed

=back

=cut

sub ocr_installed () { $OCR_INSTALLED }

1;
