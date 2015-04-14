# © 2015 SUSE Linux GmbH
# by Bernhard M. Wiedemann <bwiedemann suse de>
# Licensed under GPL v2 or later

package subtitle;
use threads;
use threads::shared;

our $fps         = 24;
our $granularity = int($fps * 0.5);
our $ssnoffset   = 0;
our $subopts     = " line:0 align:start";

sub ssn2videotime($) {
    my $ssn = shift;
    my $sec = ($ssn + $ssnoffset) / $fps;
    return sprintf("%02i:%02i.%03i", $sec / 60, $sec % 60, 1000 * ($sec - int($sec)));
}

our $subnum;
our $subtext : shared;
our $starttime;
our $subfd;

sub init_subtitle($) {
    my $filename = shift;
    open($subfd, ">", $filename) or die $!;
    print $subfd "WEBVTT FILE\n\n";
    $subtext   = '';
    $subnum    = 1;
    $starttime = undef;
}

sub finish_subtitle() {
    close $subfd;
    $subfd = undef;
}

sub add_subtitle_line($) {
    return unless $subfd;
    local $_ = shift;
    if (m/wrote screenshot #(\d+)/) {
        my $ssn = $1;
        if (($ssn % $granularity) == 0) {
            my $vt      = ssn2videotime($ssn);
            my $endtime = $vt;
            if ($subtext && $starttime) {
                print $subfd "$subnum\n$starttime --> $endtime$subopts\n$subtext\n";
                $subnum++;
                $subtext = '';
            }
            $starttime = $endtime;
        }
    }
    else {
        # filter for interesting parts
        return unless m/send_key|type_string|assert_screen|check_screen/;
        # nicify
        s/, (timeout|max_interval)=\w+//;
        s/\((?:string|key|mustmatch)='(.*)'\)/($1)/;
        s/<<< //;
        s/>>> //;
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/send_key|type_string/<b>$&<\/b>/;
        $subtext .= "$_\n";
    }
}

1;
