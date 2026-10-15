package area_ocr;
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use tinycv;
use autotest ();
use MIME::Base64 qw(decode_base64);

# OCR from the screen by coordiantes
# rect = { x => ..., y => ..., w => ..., h => ... }

# Example:
# assert_screen("field-password", timeout => 30);
# my $match = assert_screen("field-password");
# my $field = $match->{area}->[0];
# my $password_rect = {
#    x => $field->{x},
#    y => $field->{y},
#    w => int($field->{w}),
#    h => int($field->{h})
#};

sub ocr_from_screen_rect {
    my (%args) = @_;

    my $rect = $args{rect} // die "ocr_from_screen_rect: missing rect";
    for my $k (qw(x y w h)) {
        die "ocr_from_screen_rect: missing rect{$k}" unless defined $rect->{$k};
    }

    die "ocr_from_screen_rect: invalid width/height" if $rect->{w} <= 0 || $rect->{h} <= 0;

    my $psm       = $args{psm} // 7;
    my $lang      = $args{lang} // 'eng';
    my $debug     = $args{debug} // 0;
    my $whitelist = $args{whitelist} // q{abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_-+=};

    # Screenshot of the current screen via backend_last_screenshot_data
    my $rsp = autotest::query_isotovideo('backend_last_screenshot_data');
    my $raw = $rsp->{image} // q{};
    die "ocr_from_screen_rect: no screenshot data from backend" unless length $raw;

    my $img = tinycv::from_ppm(decode_base64($raw));
    die "ocr_from_screen_rect: failed to decode screenshot" unless $img;

    # Cut of the area
    my $crop = $img->copyrect($rect->{x}, $rect->{y}, $rect->{w}, $rect->{h});

    # Multiple preprocessing options
    my $dir = tempdir(CLEANUP => 1);

    my @variants = (
        {
            name   => 'base',
            img    => $crop,
            oem    => 3,
            extra  => [],
        },
        {
            name   => 'upscaled2x',
            img    => $crop->copy->scale($rect->{w} * 2, $rect->{h} * 2),
            oem    => 1,
            extra  => ['-c', 'preserve_interword_spaces=1'],
        },
    );

    my $best_text = q{};

    for my $idx (0 .. $#variants) {
        my $v = $variants[$idx];

        my $imgfn = File::Spec->catfile($dir, "crop_$idx.png");
        my $out   = File::Spec->catfile($dir, "ocr_$idx");
        my $txtfn = $out . '.txt';

        $v->{img}->write($imgfn);

        if ($debug) {
            my $debug_fn = File::Spec->catfile('/tmp', "ocr_debug_$v->{name}.png");
            $v->{img}->write($debug_fn);
        }

        my @cmd = (
            'tesseract', $imgfn, $out,
            '--oem', $v->{oem},
            '--psm', $psm,
            '-l', $lang,
            '-c', "tessedit_char_whitelist=$whitelist",
            @{$v->{extra}},
        );

        my $rc = system(@cmd);
        next if $rc != 0;
        next unless -e $txtfn;

        open my $fh, '<:encoding(UTF-8)', $txtfn or next;
        local $/;
        my $text = <$fh>;
        close $fh;
        $text =~ s/\r//g;
        chomp $text;
        $text =~ s/\s+//g;

        next unless length $text;

        $best_text = $text if length($text) > length($best_text);
        last if length($best_text) >= 6;    # lenght text
    }

    return $best_text;
}

1;
