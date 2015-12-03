package testapi;

use base Exporter;
use Exporter;
use strict;
use warnings;
use File::Basename qw(basename);
use Time::HiRes qw(sleep gettimeofday);
use Mojo::DOM;
require IPC::System::Simple;
use autodie qw(:all);

require bmwqemu;

our @EXPORT = qw($realname $username $password $serialdev %cmd %vars

  get_var check_var set_var get_var_array check_var_array autoinst_url

  send_key send_key_until_needlematch type_string type_password

  assert_screen check_screen assert_and_dclick save_screenshot
  wait_screen_change assert_and_click mouse_hide mouse_set mouse_click
  mouse_dclick mouse_tclick match_has_tag

  script_run script_sudo script_output validate_script_output
  assert_script_run assert_script_sudo

  select_console console deactivate_console reset_consoles

  upload_asset upload_image data_url assert_shutdown parse_junit_log
  upload_logs

  wait_idle wait_still_screen wait_serial record_soft_failure
  become_root x11_start_program ensure_installed eject_cd power

);

our %cmd;

our $distri;

our $realname = "Bernhard M. Wiedemann";
our $username;
our $password;

our $serialdev;

our $last_matched_needle;

sub send_key;
sub check_screen;
sub type_string;
sub type_password;

sub init {
    $serialdev = get_var('SERIALDEV', "ttyS0");
    if (get_var('OFW')) {
        $serialdev = "hvc0";
    }
    $serialdev = 'ttyS1' if check_var('BACKEND', 'ipmi');
    return;
}

sub set_distribution {
    ($distri) = @_;
    return $distri->init();
}

sub save_screenshot {
    return $autotest::current_test->take_screenshot;
}

sub record_soft_failure {
    bmwqemu::log_call('record_soft_failure');
    $autotest::current_test->{dents}++;
    return;
}

sub assert_screen {
    my ($mustmatch, $timeout) = @_;
    $timeout //= $bmwqemu::default_timeout;
    bmwqemu::log_call('assert_screen', mustmatch => $mustmatch, timeout => $timeout);
    return $last_matched_needle = bmwqemu::assert_screen(mustmatch => $mustmatch, timeout => $timeout);
}

sub check_screen {
    my ($mustmatch, $timeout) = @_;
    bmwqemu::log_call('check_screen', mustmatch => $mustmatch, timeout => $timeout);
    return $last_matched_needle = bmwqemu::assert_screen(mustmatch => $mustmatch, timeout => $timeout, check => 1);
}

sub match_has_tag {
    my ($tag) = @_;
    if ($last_matched_needle) {
        return $last_matched_needle->{needle}->has_tag($tag);
    }
    return;
}

=head2 assert_and_click, assert_and_dclick

  assert_and_click($mustmatch,[$button],[$timeout],[$click_time],[$dclick]);

deprecated: assert_and_dclick($mustmatch,[$button],[$timeout],[$click_time]);

=cut

sub assert_and_click {
    my ($mustmatch, $button, $timeout, $clicktime, $dclick) = @_;
    $timeout //= $bmwqemu::default_timeout;

    $dclick //= 0;

    $last_matched_needle = bmwqemu::assert_screen(
        mustmatch => $mustmatch,
        timeout   => $timeout
    );
    my $old_mouse_coords = $bmwqemu::backend->get_last_mouse_set();
    bmwqemu::log_call('assert_and_click', mustmatch => $mustmatch, button => $button, timeout => $timeout);

    # last_matched_needle has to be set, or the assert is buggy :)
    my $lastarea = $last_matched_needle->{area}->[-1];
    my $rx       = 1;                                                  # $origx / $img->xres();
    my $ry       = 1;                                                  # $origy / $img->yres();
    my $x        = int(($lastarea->{x} + $lastarea->{w} / 2) * $rx);
    my $y        = int(($lastarea->{y} + $lastarea->{h} / 2) * $ry);
    bmwqemu::diag("clicking at $x/$y");
    mouse_set($x, $y);
    if ($dclick) {
        mouse_dclick($button, $clicktime);
    }
    else {
        mouse_click($button, $clicktime);
    }
    # We can't just move the mouse, or we end up in a click-and-drag situation
    sleep 1;
    # move mouse back to where it was before we clicked
    return mouse_set($old_mouse_coords->{x}, $old_mouse_coords->{y});
}

sub assert_and_dclick {
    my ($mustmatch, $button, $timeout, $clicktime) = @_;
    return assert_and_click($mustmatch, $button, $timeout, $clicktime, 1);
}

=head2 wait_idle

  wait_idle([$timeout_sec]);

Wait until the system becomes idle (as configured by IDLETHESHOLD)

=cut

sub wait_idle {
    my $timeout = shift || $bmwqemu::idle_timeout;
    bmwqemu::log_call('wait_idle', timeout => $timeout);

    return bmwqemu::wait_idle($timeout);
}

=head2 wait_serial

  wait_serial($regex [[, $timeout_sec], $expect_not_found]);

Wait for $rexex to appear on serial output.
You could have sent it there earlier with

 script_run("echo Hello World E<gt> /dev/$serialdev");

Returns the string matched or undef if $expect_not_found is false
(default).

Returns undef or (after tiemout) the string that did _not_ match if
$expect_not_found is true.

=cut

sub wait_serial {

    # wait for a message to appear on serial output
    my $regexp           = shift;
    my $timeout          = shift || 90;    # seconds
    my $expect_not_found = shift || 0;     # expected can not found the term in serial output

    bmwqemu::log_call('wait_serial', regex => $regexp, timeout => $timeout);
    $timeout = bmwqemu::scale_timeout($timeout);

    my $ret = $bmwqemu::backend->wait_serial({regexp => $regexp, timeout => $timeout});
    my $matched = $ret->{matched};

    if ($expect_not_found) {
        $matched = !$matched;
    }
    sleep 1;                               # wait for one more screenshot

    # to string, we need to feed string of result to
    # record_serialresult(), either 'ok' or 'fail'
    if ($matched) {
        $matched = 'ok';
    }
    else {
        $matched = 'fail';
    }
    $autotest::current_test->record_serialresult(bmwqemu::pp($regexp), $matched);
    bmwqemu::fctres('wait_serial', "$regexp: $matched");
    return $ret->{string} if ($matched eq "ok");
    return;    # false
}

=head2 become_root

open a root shell. the implementation is distribution specific, openSUSE calls su -c bash and chdirs to /tmp

 become_root;

=cut

sub become_root {
    return $distri->become_root;
}

=head2 upload_logs

upload log file to openqa host

 upload_logs '/var/log/messages';

=cut

sub upload_logs {
    my ($file) = @_;

    bmwqemu::log_call('upload_logs', file => $file);
    type_string("curl --form upload=\@$file ");
    my $basename = basename($file);
    type_string(autoinst_url("/uploadlog/$basename") . "\n");
    wait_idle();
    return;
}

=head2 ensure_installed

distribution specific helper to install a package to test

  ensure_installed 'zsh';

=cut

sub ensure_installed {
    return $distri->ensure_installed(@_);
}

=head2 upload_asset

upload log file to openqa host

you can upload private assets only visible in the openQA
web interface:

  upload_asset '/tmp/suse.ps';

Or you can upload public assets that will have a fixed filename
replacing previous assets - useful for external users
C<upload_asset '/tmp/suse.ps';>

=cut

sub upload_asset {
    my ($file, $public) = @_;

    bmwqemu::log_call('upload_asset', file => $file);
    type_string("curl --form upload=\@$file ");
    type_string("--form target=assets_public ") if $public;
    my $basename = basename($file);
    type_string(autoinst_url("/upload_asset/$basename") . "\n");
    wait_idle();
    return;
}

=head2 wait_still_screen

  wait_still_screen([$stilltime_sec [, $timeout_sec [, $similarity_level]]])

Wait until the screen stops changing

=cut

sub wait_still_screen {
    my $stilltime        = shift || 7;
    my $timeout          = shift || 30;
    my $similarity_level = shift || (get_var('HW') ? 44 : 47);

    bmwqemu::log_call('wait_still_screen', stilltime => $stilltime, timeout => $timeout, simlvl => $similarity_level);
    return bmwqemu::wait_still_screen($stilltime, $timeout, $similarity_level);
}

sub clear_console {
    bmwqemu::log_call('clear_console');
    send_key "ctrl-c";
    sleep 1;
    send_key "ctrl-c";
    type_string "reset\n";
    sleep 2;
    return;
}

=head2 get_var

  get_var($variable [, $default ])

Return content of named openQA variable - or the default given
as 2nd argument or undef

=cut


sub get_var {
    my ($var, $default) = @_;
    return $bmwqemu::vars{$var} // $default;
}

=head2 set_var

  set_var($variable, $value);

set openQA variable - to be consumed by followup tests

=cut

sub set_var {
    my ($var, $val) = @_;
    $bmwqemu::vars{$var} = $val;
    return;
}


=head2 check_var

  check_var($variable, $value);

boolean function to check if the content of the named variable is the given
value

=cut

sub check_var {
    my ($var, $val) = @_;
    return 1 if (defined $bmwqemu::vars{$var} && $bmwqemu::vars{$var} eq $val);
    return 0;
}

=head2 get_var_array

get_var_array($variable [, $default ]);

Return the given variable as array reference (split by , | or ; )

=cut

sub get_var_array {
    my ($var, $default) = @_;
    my @vars = split(',|;', ($bmwqemu::vars{$var}));
    return $default if !@vars;
    return \@vars;
}

=head2 check_var_array

  check_var_array($variable, $value);

Boolean function to check if a value list contains a value

 check_var_array('GREETINGS', 'hallo');

=cut
sub check_var_array {
    my ($var, $val) = @_;
    my $vars_r = get_var_array($var);
    return grep { $_ eq $val } @$vars_r;
}

## helpers

sub x11_start_program {
    my ($program, $timeout, $options) = @_;
    bmwqemu::log_call('x11_start_program', timeout => $timeout, options => $options);
    return $distri->x11_start_program($program, $timeout, $options);
}

=head2 script_run

  script_run($program, [$wait_seconds]);

Run $program (by assuming the console prompt and typing it).
Wait for idle before  and after.

=cut

sub script_run {
    my ($name, $wait) = @_;
    $wait ||= $bmwqemu::idle_timeout;

    bmwqemu::log_call('script_run', name => $name, wait => $wait);
    return $distri->script_run($name, $wait);
}

=head2 assert_script_run

  assert_script_run($command);

run $command via script_run and die if it's exit status is not zero.
The exit status is checked by via magic string on the serial port.

=cut

sub assert_script_run {
    my ($cmd, $timeout) = @_;
    my $str = time;
    script_run("$cmd; echo $str-\$?- > /dev/$serialdev");
    my $ret = wait_serial("$str-\\d+-", $timeout);
    die "command '$cmd' failed" unless (defined $ret && $ret =~ /$str-0-/);
}

=head2 script_sudo

  script_sudo($program, [$wait_seconds]);

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds defaults to 2 seconds

=cut

sub script_sudo {
    my $name = shift;
    my $wait = shift || 2;

    bmwqemu::log_call('script_sudo', name => $name, wait => $wait);
    return $distri->script_sudo($name, $wait);
}

=head2 assert_script_sudo

  assert_script_sudo($command);

run $command via script_sudo and die if it's exit status is not zero.
The exit status is checked by via magic string on the serial port.

=cut

sub assert_script_sudo {
    my ($cmd) = @_;
    my $str = time;
    script_sudo("$cmd; echo $str-\$?- > /dev/$serialdev");
    my $ret = wait_serial("$str-\\d+-");
    die "command '$cmd' failed" unless (defined $ret && $ret =~ /$str-0-/);
}

=head2 power

  power($action);

Trigger backend specific power action, can be on, off, acpi or reset

  power('off');

=cut

sub power {

    # params: (on), off, acpi, reset
    my ($action) = @_;
    bmwqemu::log_call('power', action => $action);
    $bmwqemu::backend->power({action => $action});
}

=head2 eject_cd

  eject_cd;

if backend supports it, eject the CD

=cut

sub eject_cd {
    bmwqemu::log_call('eject_cd');
    $bmwqemu::backend->eject_cd;
}

## keyboard

=head2 send_key

  send_key($qemu_key_name[, $wait_idle]);

=cut

sub send_key {
    my ($key, $wait) = @_;
    $wait //= 0;
    bmwqemu::log_call('send_key', key => $key);
    eval { $bmwqemu::backend->send_key($key); };
    bmwqemu::mydie("Error send_key key=$key: $@\n") if ($@);
    wait_idle() if $wait;
}

=head2 send_key_until_needlematch

  send_key_until_needlematch($tag, $key, [$counter, $timeout]);

Send specific key if can not find the matched needle.

=cut

sub send_key_until_needlematch {
    my ($tag, $key, $counter, $timeout) = @_;

    $counter //= 20;
    $timeout //= 1;
    while (!check_screen($tag, $timeout)) {
        send_key $key;
        if (!$counter--) {
            assert_screen $tag, 1;
        }
    }
}

=head2 type_string

  type_string($string [ , max_interval => <num> ] [, secret => 1 ] );

send a string of characters, mapping them to appropriate key names as necessary

you can pass optional paramters with following keys:

max_interval (1-250) determines the typing speed, the lower the
max_interval the slower the typing.

secret (bool) suppresses logging of the actual string typed.

=cut

sub type_string {
    # special argument handling for backward compat
    my $string = shift;
    my %args;
    if (@_ == 1) {    # backward compat
        %args = (max_interval => $_[0]);
    }
    else {
        %args = @_;
    }
    my $log = $args{secret} ? 'SECRET STRING' : $string;
    my $max_interval = $args{max_interval} // 250;
    bmwqemu::log_call('type_string', string => $log, max_interval => $max_interval);
    $bmwqemu::backend->type_string({text => $string, max_interval => $max_interval});
}

=head2 type_password

  type_password([$password]);

A convience wrappar around type_string, which doesn't log the string and uses $testapi::password
if no string is given

=cut

sub type_password {
    my ($string) = @_;
    $string //= $password;
    type_string $string, max_interval => 100, secret => 1;
}

## keyboard end

## mouse
sub mouse_set {
    my ($mx, $my) = @_;

    bmwqemu::log_call('mouse_set', x => $mx, y => $my);
    $bmwqemu::backend->mouse_set({x => $mx, y => $my});
}

sub mouse_click {
    my $button = shift || 'left';
    my $time   = shift || 0.15;
    bmwqemu::log_call('mouse_click', button => $button, cursor_down => $time);
    $bmwqemu::backend->mouse_button($button, 1);
    # FIXME sleep resolution = 1s, use usleep
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
}

sub mouse_dclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::log_call('mouse_dclick', button => $button, cursor_down => $time);
    $bmwqemu::backend->mouse_button($button, 1);
    # FIXME sleep resolution = 1s, use usleep
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 1);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
}

sub mouse_tclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::log_call('mouse_tclick', button => $button, cursor_down => $time);
    $bmwqemu::backend->mouse_button($button, 1);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 1);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 1);
    sleep $time;
    $bmwqemu::backend->mouse_button($button, 0);
}

sub mouse_hide(;$) {
    my $border_offset = shift || 0;
    bmwqemu::log_call('mouse_hide', border_offset => $border_offset);
    $bmwqemu::backend->mouse_hide($border_offset);
}
## mouse end

=head2 autoinst_url

returns the base URL to contact the local os-autoinst service. You can also pass
a path as argument to append it automatically.

  script_run("curl " . autoinst_url . "/data");

=cut

sub autoinst_url {
    my ($path, $query) = @_;
    $path  //= '';
    $query //= {};

    # in a kvm instance you reach the VM's host under 10.0.2.2
    my $qemuhost = '10.0.2.2';
    my $hostname = get_var('WORKER_HOSTNAME') || $qemuhost;

    # QEMUPORT is historical for the base port of the worker instance
    my $workerport = get_var("QEMUPORT") + 1;

    my $token       = get_var('JOBTOKEN');
    my $querystring = join('&', map { "$_=$query->{$_}" } sort keys %$query);
    my $url         = "http://$hostname:$workerport/$token$path";
    $url .= "?$querystring" if $querystring;

    return $url;
}

=head2 data_url

  data_url($name);

returns the URL to download data or asset file
Special values REPO_\d and ASSET_\d points to the asset configured
in the corresponding variable

=cut

sub data_url($) {
    my ($name) = @_;
    if ($name =~ /^REPO_\d$/) {
        return autoinst_url("/assets/repo/" . get_var($name));
    }
    if ($name =~ /^ASSET_\d$/) {
        return autoinst_url("/assets/other/" . get_var($name));
    }
    else {
        return autoinst_url("/data/$name");
    }
}

=head2 script_output

script_output($script, [$wait])

fetches the script through HTTP into the VM and execs it with bash -xe and directs
stdout (*not* stderr!) to the serial console and returns the output *if* the script
exists with 0. Otherwise the test is set to failed.

The default timeout for the script is 10 seconds. If you need more, pass a 2nd parameter

=cut

sub script_output($;$) {
    my $wait;
    ($commands::current_test_script, $wait) = @_;
    $commands::current_test_script .= "\necho SCRIPT_FINISHED\n";
    $wait ||= 10;

    my $suffix = bmwqemu::random_string();
    type_string "curl -f -v " . autoinst_url("/current_script") . " > /tmp/script$suffix.sh && echo \"curl-\$?\" > /dev/$serialdev\n";
    wait_serial('curl-0') || die "script couldn't be downloaded";
    send_key "ctrl-l";

    type_string "/bin/bash -ex /tmp/script$suffix.sh | tee /dev/$serialdev\n";
    my $output = wait_serial('SCRIPT_FINISHED', $wait) or die "script failed";

    # strip the internal exit catcher
    $output =~ s,SCRIPT_FINISHED,,;

    # trim whitespaces
    $output =~ s/^\s+|\s+$//g;

    return $output;
}

=head2 validate_script_output

validate_script_output($script, $code, [$wait])

wrapper around script_output, that runs a callback on the output. Use it as

validate_script_output "cat /etc/hosts", sub { m/127.*localhost/ }

=cut

sub validate_script_output($&;$) {
    my ($script, $code, $wait) = @_;
    $wait ||= 10;

    my $output = script_output($script, $wait);
    return unless $code;
    my $res = 'ok';

    # set $_ so the callbacks can be simpler code
    $_ = $output;
    if (!$code->()) {
        $res = 'fail';
        bmwqemu::diag("output does not pass the code block:\n$output");
    }
    # abusing the function
    $autotest::current_test->record_serialresult($output, $res);
    if ($res eq 'fail') {
        die "output not validating";
    }
}

=head2 wait_screen_change

  wait_screen_change($code);

wrapper around code that is supposed to change the screen. This is basically the
opposite to wait_still_screen. Make sure to put the commands to change the screen
within the block to avoid races between the action and the screen change

  wait_screen_change {
     send_key 'esc';
  }

=cut

sub wait_screen_change(&@) {
    my ($callback) = @_;

    bmwqemu::log_call('wait_screen_change');

    # get the initial screen
    my $refimg = bmwqemu::getcurrentscreenshot();
    $callback->() if $callback;

    my $starttime        = time;
    my $timeout          = 10;
    my $similarity_level = 50;

    while (time - $starttime < $timeout) {
        my $img = bmwqemu::getcurrentscreenshot();
        my $sim = $img->similarity($refimg);
        print "waiting for screen change: " . (time - $starttime) . " $sim\n";
        if ($sim < $similarity_level) {
            bmwqemu::fctres('wait_screen_change', "screen change seen at " . (time - $starttime));
            return 1;
        }
        sleep(0.5);
    }
    save_screenshot;
    bmwqemu::fctres('wait_screen_change', "timed out");
    return 0;
}

## helpers end

=head1 multi console support

All testapi commands that interact with the system under test do that
through a console.  C<send_key>, C<type_string> type into a console.
C<assert_screen> 'looks' at a console, C<assert_and_click> looks at
and clicks on a console.

Most backends support several consoles in some way.  These consoles
then have names as defined by the backend.

Consoles can be selected for interaction with the system under test.  
One of them is 'selected' by default, as defined by the backend.

There are no consoles predefined by default, the distribution has
to add them during initial setup and define actions on what should
happen when they are selected first by the tests.

E.g. your distribution can give e.g. tty2 and tty4 a name for the
tests to select

  $self->add_console('root-console',  'tty-console', {tty => 2});
  $self->add_console('user-console',  'tty-console', {tty => 4});

=out

=item C<select_console("root-console")>

Select the named console for further testapi interaction (send_text,
send_key, wait_screen_change, ...)

If this the first time, a test selects this console, the distribution
will get a call into activate_console('root-console', $console_obj) to
make sure to actually log in root. For the backend it's just a tty
object (in this example) - so it will sure the console is active,
but to setup the root shell on this console, the distribution needs
to run test code.

=item C<add_console("console", "console type" [, optional console parameters...])>

You need to do this in your distribution and not in tests. It will not trigger
any action on the system under test, but only store the parameters.

The console parameters are backend specific.

=item C<deactivate_console("testapi_console")>

Deactivate, i.e. disconnect, 'turn off' a console, free local
ressources associated with it.  The system under test can deactivate
consoles.  It is a fatal ('die ...') error to give commands to
deactivated consoles.

It is a fatal ('die ...') error to give commands to inactive consoles.

=item C<console("testapi_console")->$console_command(@console_command_args)>

Some consoles have special commands beyond C<type_string>, C<assert_screen>

Such commands can be accessed using this API.

C<console("bootloader")>, C<console("errorlog")>, ... returns a proxy
object for the specific console which can then be directly accessed.

This is also useful for typing/interacting 'in the background',
without turning the video away from the currently selected console.

Note: C<assert_screen()> and friends look at the currently selected
console (select_console), no matter which console you send commands to
here.

=back

=cut


require backend::console_proxy;
our %testapi_console_proxies;

sub select_console {
    my ($testapi_console) = @_;
    bmwqemu::log_call('select_console', testapi_console => $testapi_console);
    if (!exists $testapi_console_proxies{$testapi_console}) {
        $testapi_console_proxies{$testapi_console} = backend::console_proxy->new($testapi_console);
    }
    my $ret = $bmwqemu::backend->select_console({testapi_console => $testapi_console});

    if ($ret->{activated}) {
        $testapi::distri->activate_console($testapi_console);
    }
    return $testapi_console_proxies{$testapi_console};
}

sub deactivate_console {
    my ($testapi_console) = @_;
    unless (exists $testapi_console_proxies{$testapi_console}) {
        warn "deactivate_console: console $testapi_console is not activated";
        return;
    }
    bmwqemu::log_call('deactivate_console', testapi_console => $testapi_console);
    my $ret = $bmwqemu::backend->deactivate_console({testapi_console => $testapi_console});
    delete $testapi_console_proxies{$testapi_console};
    return $ret;
}

sub console {
    my ($testapi_console) = @_;
    bmwqemu::log_call('console', testapi_console => $testapi_console);
    if (exists $testapi_console_proxies{$testapi_console}) {
        return $testapi_console_proxies{$testapi_console};
    }
    die "console $testapi_console is not activated.";
}

=head2 reset_consoles
 
  reset_consoles;

will make sure the next select_console will activate the console. This is important
if you did something to the system that affects the console (e.g. trigger reboot).

=cut

sub reset_consoles {
    # we iterate through all consoles selected through the API
    for my $console (keys %testapi_console_proxies) {
        $bmwqemu::backend->reset_console({testapi_console => $console});
    }
    return;
}

sub assert_shutdown {
    my ($timeout) = @_;
    $timeout //= 60;
    bmwqemu::log_call('assert_shutdown', timeout => $timeout);
    while ($timeout >= 0) {
        my $status = $bmwqemu::backend->status() // '';
        if ($status eq 'shutdown') {
            $autotest::current_test->take_screenshot('ok');
            return;
        }
        --$timeout;
        sleep 1 if $timeout >= 0;
    }
    $autotest::current_test->take_screenshot('fail');
    die "Machine didn't shut down!";
}

=head2 parse_junit_log

  parse_junit_log("report.xml");

Upload log file from SUT (calls upload_logs internally). The uploaded
file is then parsed as jUnit format and extra test results are created from it.

=cut

sub parse_junit_log {
    my ($file) = @_;

    upload_logs($file);

    $file = basename($file);

    open my $fd, "<", "ulogs/$file";
    my $xml = join("", <$fd>);
    close $fd;

    my $dom = Mojo::DOM->new($xml);

    my @tests;

    for my $ts ($dom->find('testsuite')->each) {
        my $ts_category = $ts->{package};
        $ts_category =~ s/[^A-Za-z0-9._-]/_/g;    # the name is used as part of url so we must strip special characters
        my $ts_name = $ts_category;
        $ts_category =~ s/\..*$//;
        $ts_name =~ s/^[^.]*\.//;
        $ts_name =~ s/\./_/;

        push @tests,
          {
            flags    => {important => 1},
            category => $ts_category,
            name     => $ts_name,
            script   => $autotest::current_test->{script},
          };

        my $ts_result = 'ok';
        $ts_result = 'fail' if $ts->{failures} || $ts->{errors};

        my $result = {
            result  => $ts_result,
            details => [],
            dents   => 0,
        };

        my $num = 1;
        for my $tc ($ts, $ts->children('testcase')->each) {

            # create extra entry for whole testsuite  if there is any system-out or system-err outside of particular testcase
            next if ($tc->tag eq 'testsuite' && $tc->children('system-out, system-err')->size == 0);

            my $tc_result = $ts_result;    # use overall testsuite result as fallback
            $tc_result = 'ok'   if defined $tc->{status} && $tc->{status} eq 'success';
            $tc_result = 'fail' if defined $tc->{status} && $tc->{status} ne 'success';

            my $details = {result => $tc_result};

            my $text_fn = "$ts_category-$ts_name-$num.txt";
            open my $fd, ">", bmwqemu::result_dir() . "/$text_fn";
            print $fd "# $tc->{name}\n";
            for my $out ($tc->children('system-out, system-err, failure')->each) {
                print $fd "# " . $out->tag . ": \n\n";
                print $fd $out->text . "\n";
            }
            close $fd;
            $details->{text}  = $text_fn;
            $details->{title} = $tc->{name};

            push @{$result->{details}}, $details;
            $num++;
        }

        my $fn = bmwqemu::result_dir() . "/result-$ts_name.json";
        bmwqemu::save_json_file($result, $fn);
    }

    return $autotest::current_test->register_extra_test_results(\@tests);
}

1;

# vim: set sw=4 et:
