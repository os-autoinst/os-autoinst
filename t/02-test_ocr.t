#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::Output;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings ':report_warnings';
use Test::MockModule;
use Test::MockObject;
use File::Basename;
use File::Temp 'tempdir';
use File::Spec::Functions 'catfile';
use Encode 'encode';
use ocr;
use tinycv;


subtest 'ocr_installed' => sub {
    my $ocr_installed_sav = $ocr::OCR_INSTALLED;
    $ocr::OCR_INSTALLED = undef;
    ok(!ocr_installed(), 'Check retval if OCR program is not installed');
    $ocr::OCR_INSTALLED = '/usr/bin/ocr_prog';
    ok(ocr_installed(), 'Check retval if OCR program is installed');
    $ocr::OCR_INSTALLED = $ocr_installed_sav;
};

subtest 'img_to_str' => sub {
    my $ocr_str = 'value';
    my $img = tinycv::read(dirname(__FILE__) . '/data' . '/bootmenu.test.png');
    stderr_like(
        sub { is(img_to_str(3), undef, 'Check undef for scalar argument'); },
        qr/.*Not a reference to object with type tinycv::Image \(internal error, probably a bug\)\!.*/,
        'Check stderr for scalar argument');
    $ocr_str = 'value';
    my $obj = {4 => 5};
    bless $obj;
    stderr_like(
        sub { is(img_to_str($obj), undef, 'Check undef for wrong object argument'); },
        qr/.*Not a reference to object with type tinycv::Image \(internal error, probably a bug\)\!.*/,
        'Check stderr for HASH ref argument');

    $img = tinycv::read(dirname(__FILE__) . '/data' . '/bootmenu.test_1200x900.png');
    my $xpos = 0;
    my $ypos = 254;
    my $width = 200;
    my $height = 17;
    my $img_area = $img->copyrect($xpos, $ypos, $width, $height);

    {
        no warnings qw(redefine prototype);
        no strict 'refs';
        my $saved_func = \&tinycv::Image::write;
        *{'tinycv::Image::write'} = sub { return undef; };
        stderr_like(
            sub { is(img_to_str($img_area), undef, 'Check undef if writing img failed'); },
            qr/.*Writing image to prepare for OCR failed!.*/,
            'Check stderr for failed writing of img.');
        *{'tinycv::Image::write'} = $saved_func;
    }

  SKIP: {
        skip('The OCR program is not installed.', 1)
          unless (ocr_installed());

        # Some checks that require ugly overrides.
        {
            my $fakepath = tempdir();
            my $fakeocr = catfile($fakepath, 'gocr');
            my $fakeocr_content = encode('UTF-8', "#!/usr/bin/env sh\necho 'I am fake' 1>&2\nexit 1");
            open(my $fakeocr_fh, '>', $fakeocr);

            # print seems to be swallowed by the test framework
            syswrite($fakeocr_fh, $fakeocr_content, length($fakeocr_content));

            close($fakeocr_fh);
            chmod(0755, $fakeocr);
            my $path_sav = $ENV{PATH};
            $ENV{PATH} = $fakepath . ':' . $ENV{PATH};
            stderr_like(
                sub { is(img_to_str($img_area), undef, 'Check undef if OCR program has failed.'); },
                qr/.*The OCR program exited with error.*/,
                'Check stderr for failed OCR program.');
            $ENV{PATH} = $path_sav;
        }

        $xpos = 0;
        $ypos = 254;
        $width = 1025;
        $height = 17;
        $img_area = $img->copyrect($xpos, $ypos, $width, $height);
        stderr_like(
            sub { is(img_to_str($img_area), undef, 'Check undef for exceeding horizontal pixel count'); },
            qr/.*Skipping OCR evaluation of image, resolution too high \(max:.*/,
            'Check stderr for exceeding horizontal pixel count');

        $xpos = 256;
        $ypos = 0;
        $width = 194;
        $height = 769;
        $img_area = $img->copyrect($xpos, $ypos, $width, $height);
        stderr_like(
            sub { is(img_to_str($img_area), undef, 'Check undef for exceeding vertical pixel count'); },
            qr/.*Skipping OCR evaluation of image, resolution too high \(max\:.*/,
            'Check stderr for exceeding vertical pixel count');

        $img = tinycv::read(dirname(__FILE__) . '/data' . '/bootmenu.test.png');
        $xpos = 256;
        $ypos = 254;
        $width = 194;
        $height = 17;
        $img_area = $img->copyrect($xpos, $ypos, $width, $height);
        $ocr_str = img_to_str($img_area);
        note("Found OCR String:\n$ocr_str");
        ok($ocr_str eq 'Check Installation Media', 'Check single line OCR');

        $xpos = 212;
        $ypos = 551;
        $width = 128;
        $height = 43;
        $img_area = $img->copyrect($xpos, $ypos, $width, $height);
        $ocr_str = img_to_str($img_area);
        note("Found OCR String:\n$ocr_str");
        ok($ocr_str eq "F3 Video Mode\n   Default", 'Check multi line OCR');
    }
};

done_testing;

