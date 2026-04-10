# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::LLMAnalysis;
use Mojo::Base -signatures;
use bmwqemu;
use Feature::Compat::Try;
use IPC::Run ();
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);
use Mojo::File qw(path);
use Text::ParseWords;

use constant MAX_PAYLOAD_SIZE => 8000;

sub _get_file_tail ($filename, $result_dir, $max_lines) {
    my $file = $filename;
    $file = "$result_dir/$filename" unless -e $file;
    return '' unless -e $file;
    my $tail = qx(tail -n $max_lines \Q$file\E 2>/dev/null) || '';
    chomp $tail;
    return $tail;
}

sub gather_context ($result_dir) {
    my @failed_tests;
    for my $res_file (glob "$result_dir/result-*.json") {
        my $json = eval { decode_json(path($res_file)->slurp) };
        next unless $json && ($json->{result} // '') eq 'fail';
        my $name = $json->{name};
        ($name) = $res_file =~ /result-(.*)\.json$/ unless $name;
        push @failed_tests, $name if $name;
    }
    return undef unless @failed_tests;
    my $failed_str = join ', ', @failed_tests;
    my $log_tail = _get_file_tail('autoinst-log.txt', $result_dir, 200);
    my $serial_tail = _get_file_tail('serial0', $result_dir, 100);
    my $context = {
        failed_tests => $failed_str,
        log_tail => $log_tail,
        serial_tail => $serial_tail,
        distri => $bmwqemu::vars{DISTRI} || 'unknown',
        version => $bmwqemu::vars{VERSION} || 'unknown',
        arch => $bmwqemu::vars{ARCH} || 'unknown',
    };
    return $context;
}

sub build_prompt ($context) {
    my $distri = $context->{distri};
    my $version = $context->{version};
    my $arch = $context->{arch};
    my $failed_tests = $context->{failed_tests};
    my $log_tail = $context->{log_tail};
    my $serial_tail = $context->{serial_tail};

    # Truncate inputs to preserve instructions at the end of the prompt
    $log_tail = substr $log_tail, -MAX_PAYLOAD_SIZE if length($log_tail) > MAX_PAYLOAD_SIZE;
    $serial_tail = substr $serial_tail, -MAX_PAYLOAD_SIZE if length($serial_tail) > MAX_PAYLOAD_SIZE;

    my $prompt = <<~"EOF";
        You are analyzing an automated test run of $distri $version $arch.
        The following tests failed: $failed_tests.

        Relevant log tail:
        $log_tail

        Serial output tail:
        $serial_tail

        Provide exactly 2-3 sentences answering:
        1. Why did the tests fail?
        2. What should be done to prevent these failures?
        3. Is this likely a product regression or a test infrastructure problem
           (false positive)?
        EOF

    return $prompt;
}

sub query_llm_api ($prompt, $url, $model) {
    my $ua = Mojo::UserAgent->new;
    $ua->connect_timeout(300);
    $ua->inactivity_timeout(300);
    my $req = {
        model => $model,
        messages => [{role => 'user', content => $prompt}],
        temperature => 0.3
    };
    my $tx = $ua->post($url => json => $req);
    if (my $err = $tx->error) {
        return 'Error: HTTP API failed with status ' . $err->{code} if $err->{code};
        return 'Error: ' . ($err->{message} || 'Connection failed');
    }
    my $res = $tx->result;
    my $json = eval { decode_json($res->body) };
    return $json->{choices}[0]{message}{content} if $json && $json->{choices} && $json->{choices}[0]{message}{content};
    return 'Error: Unexpected response format from LLM API.';
}

sub query_llm_cmd ($prompt, $cmd) {
    my @cmd_array = Text::ParseWords::shellwords($cmd);
    my $out;
    my $err;
    try {
        my $success = IPC::Run::run(\@cmd_array, \$prompt, \$out, \$err, IPC::Run::timeout(300));
        return "Error: Command exited with $? - " . ($err || $out || '') unless $success;
    } catch ($e) { return "Error: Command failed - $e" }
    return $out || $err || 'Error: Command produced no output.';
}

sub run ($result_dir) {
    my $context = gather_context($result_dir);
    return unless $context;
    bmwqemu::diag('Starting LLM Analysis…');
    my $prompt = build_prompt($context);
    my $output;
    if (my $cmd = $bmwqemu::vars{LLM_FAILURE_ANALYSIS_CMD}) {
        $output = query_llm_cmd($prompt, $cmd);
    }
    else {
        my $url = $bmwqemu::vars{LLM_FAILURE_ANALYSIS_URL} || 'http://localhost:8080/v1/chat/completions';
        my $model = $bmwqemu::vars{LLM_FAILURE_ANALYSIS_MODEL} || 'gemma-4-26B-A4B-it';
        $output = query_llm_api($prompt, $url, $model);
    }
    path("$result_dir/llm-failure-analysis.txt")->spew($output);
    bmwqemu::diag("LLM Analysis:\n$output\nSaved to $result_dir/llm-failure-analysis.txt");
    my $analysis_result = {
        name => '00-llm_failure_analysis',
        result => 'ok',
        details => [{
                title => 'LLM Failure Analysis',
                result => 'info',
                text => 'llm-failure-analysis.txt',
        }],
    };
    bmwqemu::save_json_file($analysis_result, "$result_dir/result-00-llm_failure_analysis.json");
}

1;
