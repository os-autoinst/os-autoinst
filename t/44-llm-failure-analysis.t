#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Test::MockModule;
use Mojo::Base -signatures;
use Mojo::File qw(path tempdir);
use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/..", "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use bmwqemu;
use OpenQA::Isotovideo::LLMAnalysis;

my $tmpdir = tempdir;
chdir $tmpdir or die "Cannot chdir to $tmpdir: $!";
$bmwqemu::result_dir = 'testresults';

sub setup_results (@results) {
    my $testresults = path($bmwqemu::result_dir);
    $testresults->make_path;
    $testresults->list->each(sub ($f, $) { $f->remove });

    my $i = 1;
    for my $res (@results) {
        $testresults->child("result-$i.json")->spew(qq({"name":"test$i", "result":"$res"}));
        $i++;
    }
}

subtest 'Context gathering and truncation' => sub {
    setup_results('ok', 'fail');
    ok OpenQA::Isotovideo::LLMAnalysis::gather_context($bmwqemu::result_dir), 'Returns context when failures exist';

    setup_results('ok');
    ok !OpenQA::Isotovideo::LLMAnalysis::gather_context($bmwqemu::result_dir), 'Skips when no failures';

    # Missing names
    setup_results('fail');
    path($bmwqemu::result_dir)->child('result-1.json')->spew('{"result":"fail"}');
    my $ctx = OpenQA::Isotovideo::LLMAnalysis::gather_context($bmwqemu::result_dir);
    is $ctx->{failed_tests}, '1', 'Fallback to filename for test name';

    # Truncation logic
    path($bmwqemu::result_dir)->child('autoinst-log.txt')->spew(join "\n", map { "L$_" } 1 .. 300);
    path($bmwqemu::result_dir)->child('serial0')->spew(join "\n", map { "S$_" } 1 .. 150);
    $ctx = OpenQA::Isotovideo::LLMAnalysis::gather_context($bmwqemu::result_dir);
    is scalar(split "\n", $ctx->{log_tail}), 200, 'Log tail truncated';
    is scalar(split "\n", $ctx->{serial_tail}), 100, 'Serial tail truncated';

    # Empty files
    path($bmwqemu::result_dir)->child('autoinst-log.txt')->spew('');
    path($bmwqemu::result_dir)->child('serial0')->spew('');
    $ctx = OpenQA::Isotovideo::LLMAnalysis::gather_context($bmwqemu::result_dir);
    is $ctx->{log_tail}, '', 'Handles empty log';
};

subtest 'Prompt generation' => sub {
    my $ctx = {distri => 'D', version => 'V', arch => 'A', failed_tests => 'F', log_tail => 'L', serial_tail => 'S'};
    my $prompt = OpenQA::Isotovideo::LLMAnalysis::build_prompt($ctx);
    like $prompt, qr/D V A.*F.*L.*S/s, 'Prompt contains all context';

    my $long = 'A' x 10000;
    $ctx->{log_tail} = $long;
    $ctx->{serial_tail} = $long;
    $prompt = OpenQA::Isotovideo::LLMAnalysis::build_prompt($ctx);
    ok length($prompt) < 17000, 'Prompt truncated';
    like $prompt, qr/sentences answering/s, 'Instructions preserved at end';
};

subtest 'HTTP API mode' => sub {
    my $mock_ua = Test::MockModule->new('Mojo::UserAgent');
    require Mojo::Transaction::HTTP;
    require Mojo::Message::Response;

    my $test_api = sub ($res_body, $res_error = undef) {
        $mock_ua->redefine(post => sub {
                my $tx = Mojo::Transaction::HTTP->new;
                $tx->res->code(200);
                $tx->res->body($res_body) if defined $res_body;
                $tx->res->error($res_error) if $res_error;
                return $tx;
        });
        return OpenQA::Isotovideo::LLMAnalysis::query_llm_api('p', 'u', 'm');
    };

    is $test_api->('{"choices":[{"message":{"content":"OK"}}]}'), 'OK', 'Success path';
    like $test_api->(undef, {message => 'Fail', code => 500}), qr/status 500/, 'HTTP error';
    is $test_api->(undef, {message => 'Timeout'}), 'Error: Timeout', 'Connection error';
    is $test_api->('{"malformed":1}'), 'Error: Unexpected response format from LLM API.', 'Malformed JSON';
    is $test_api->('Not JSON'), 'Error: Unexpected response format from LLM API.', 'Non-JSON response';
    is $test_api->('{"choices":[]}'), 'Error: Unexpected response format from LLM API.', 'Empty choices';
};

subtest 'CLI command mode' => sub {
    my $mock_ipc = Test::MockModule->new('IPC::Run');
    my $test_cmd = sub ($out, $err, $exit_code, $die_msg = undef) {
        $mock_ipc->redefine(run => sub ($cmd, $in, $out_ref, $err_ref, @rest) {
                die $die_msg if $die_msg;
                $$out_ref = $out;
                $$err_ref = $err;
                $? = $exit_code << 8;
                return $exit_code == 0;
        });
        return OpenQA::Isotovideo::LLMAnalysis::query_llm_cmd('p', 'c');
    };

    is $test_cmd->('Out', '', 0), 'Out', 'Success path';
    like $test_cmd->('', '', 0, 'dead'), qr/Command failed - dead/, 'Command death';
    like $test_cmd->('Out', 'Err', 1), qr/exited with 256 - Err/, 'Non-zero exit with stderr';
    like $test_cmd->('Out', '', 1), qr/exited with 256 - Out/, 'Non-zero exit with stdout only';
    is $test_cmd->('', '', 0), 'Error: Command produced no output.', 'No output';
};

subtest 'Execution routing' => sub {
    my $mock_llm = Test::MockModule->new('OpenQA::Isotovideo::LLMAnalysis');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('diag');

    $mock_llm->redefine(gather_context => sub { return {distri => 'D'} });
    $mock_llm->redefine(build_prompt => sub { return 'P' });
    $mock_llm->redefine(query_llm_api => sub { return 'api' });
    $mock_llm->redefine(query_llm_cmd => sub { return 'cmd' });

    delete $bmwqemu::vars{LLM_FAILURE_ANALYSIS_CMD};
    OpenQA::Isotovideo::LLMAnalysis::run($bmwqemu::result_dir);
    is path($bmwqemu::result_dir)->child('llm-failure-analysis.txt')->slurp, 'api', 'Default to API';

    $bmwqemu::vars{LLM_FAILURE_ANALYSIS_CMD} = 'c';
    OpenQA::Isotovideo::LLMAnalysis::run($bmwqemu::result_dir);
    is path($bmwqemu::result_dir)->child('llm-failure-analysis.txt')->slurp, 'cmd', 'Route to CMD';

    $mock_llm->redefine(gather_context => sub { return undef });
    $mock_bmwqemu->redefine(diag => sub { die 'No context should return' });
    ok !OpenQA::Isotovideo::LLMAnalysis::run($bmwqemu::result_dir), 'Early return if no context';
};

done_testing;
chdir '/';
