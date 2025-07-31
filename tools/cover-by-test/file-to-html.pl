#!/usr/bin/perl
use strict;
use warnings;
use v5.10;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Data::Dumper;

my $giturl = "https://github.com/os-autoinst/os-autoinst/blob";
my ($dir, $sha, $file) = @ARGV;
$sha //= 'HEAD';
my $code_file = $file =~ s{$dir/}{}r;
$code_file =~ s/\.json//;

my $by_test = decode_json path($file)->slurp;
my @code = split m/\n/, path($code_file)->slurp;
shift @$by_test;

my %all_tests;
for my $tests (@$by_test) {
    my @testfiles = sort keys %$tests;
    @all_tests{@testfiles} = ();
}
my @all_tests = sort keys %all_tests;
say sprintf "%-40s covered by %2d tests", $code_file, scalar @all_tests;
for my $i (0 .. $#all_tests) {
    $all_tests{$all_tests[$i]} = $i;
}

my $html = <<"EOM";
<html><head><title>Coverage By Test $code_file</title>
<style>
table.coverage tr th, table.coverage tr td {
    border-collapse: collapse;
    font-family: monospace;
    border-top: 0px;
    white-space: nowrap;
    white-space: pre;
}
table.coverage tr th {
    border: 0px solid #eee;
    background-color: white;
}
table.coverage tr td {
    background-color: #f8f8f8;
    border: 1px solid #eee;
}
table.coverage thead tr th {
    background-color: none;
    border-bottom: 2px solid #bbb;
}
table.coverage thead {
    position: -webkit-sticky;
    position: sticky;
    z-index: 2;
    top: 0;
}
table.coverage tr td.code {
    min-width: 30em;
    max-width: 50em;
    overflow: hidden;
}
table.coverage tr td.comment {
    background-color: #ddd;
    color: #666;
}
table.coverage tr td.uncovered_code {
    color: #303030;
    background-color: #f8f8f8;
}
table.coverage tr td.covered_code {
    background-color: #bbffdd;
}
table.coverage tr td.covered {
    color: #303030;
    width: 2em;
    background-color: #bbffdd;
    text-align: center;
}
table.coverage tr td.uncovered {
    color: #ff0000;
    width: 2em;
}
table.coverage a.code_link {
    text-decoration: none;
    color: black;
}
table.coverage th.filename {
    text-align: center;
    vertical-align: bottom;
    padding: 1em;
}
table.coverage th.filename span {
    width: 100%;
    margin-bottom: 3em;
    padding: 1em;
    font-size: 150%;
}
table.coverage th.testfile {
    text-align: left;
    height: 11em;
    font-weight: normal;
}
table.coverage th.testfile > div {
    transform: translate(14px, 4em) rotate(310deg);
    width: 2em;
}
th.testfile > div > span {
  border-bottom: 1px solid #5b9;
  padding: 1px 2px;
}
a:target { background-color: yellow }
</style>
</head>
<body>
<table class="coverage" _border="1" cellspacing="0" cellpadding="0"><thead>
<tr class="header">
EOM

$html .= qq{<th></th><th class="filename"><span>$code_file</span></th>};
for my $i (0 .. $#all_tests) {
    $html .= qq{<th class="testfile"><div><span><a class="code_link" href="$giturl/$sha/$all_tests[$i]">$all_tests[$i]</a></span></div></th>};
}
$html .= "</tr>";
$html .= "</thead><tbody>";

my $in_pod = 0;
for my $i (0 .. $#code) {
    my $line = $code[$i];
    my $tests = $by_test->[$i] || {};
    my @testfiles = sort keys %$tests;
    my $class = "code";
    my $comment;
    my $end;
    if ($line =~ m/^ *#/) {
        $comment = 1;
    }
    if (not $in_pod) {
        $in_pod = 1 if $line =~ m/^=\w+/;
    }
    if ($line =~ m/^__(END|DATA__)$/) {
        $end = 1;
    }
    if (@testfiles) {
        $class .= " covered_code";
    }
    elsif ($comment or $in_pod or $end) {
        $class .= " comment";
    }
    else {
        $class .= " uncovered_code";
    }
    my @cols;
    for my $file (@testfiles) {
        my $num = $all_tests{$file};
        $cols[$num] = $file;
    }
    my $cols = join '', map {
        sprintf '<td class="%s">%s</td>', $_ ? ('covered', 'X') : ('uncovered', '')
    } @cols[0..$#all_tests];

    my $line_no = $i + 1;
    $html .= <<"EOM";
<tr >
<th><a class="code_link" name="L$line_no" href="#L$line_no">$line_no</a></th>
<td class="$class"><a class="code_link" href="$giturl/$sha/$code_file#L$line_no">$line</a></th>
$cols
<td></td>
</tr>
EOM

    if ($in_pod) {
        $in_pod = 0 if $line =~ m/^=cut/;
    }
}

$html .= <<'EOM';
</tbody></table>
</body></html>
EOM

$file =~ s/\.json/.html/;
path($file)->spew($html);
