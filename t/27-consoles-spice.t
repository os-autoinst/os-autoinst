#!/usr/bin/perl

use Test::Most;
use Mojo::Base -signatures;

use FindBin qw($Bin);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Warnings qw(:all :report_warnings);
use Test::Output qw(stderr_like);

use consoles::spice_base;
use consoles::SPICE;
require tinycv;

my $c = consoles::spice_base->new('sut', {});
my $spice = Test::MockObject->new;
$c->{vnc} = $spice;

subtest 'basic stubs' => sub {
    $spice->set_always('width', 1024);
    $spice->set_always('height', 768);
    is $c->mouse_width, 1024, 'width retrieved';
    is $c->mouse_height, 768, 'height retrieved';
};

subtest 'keyboard input' => sub {
    $spice->set_true('map_and_send_key');
    lives_ok { $c->send_key_event('ret', 0.1) } 'send_key_event works';
    ok $spice->called('map_and_send_key'), 'map_and_send_key was called';
};

subtest 'mouse input' => sub {
    $spice->set_true('mouse_move_to');
    $c->mouse_move_to(100, 200);
    ok $spice->called('mouse_move_to'), 'mouse_move_to was called';
    is_deeply $c->{mouse}, {x => 100, y => 200}, 'mouse coordinates updated';

    $spice->set_true('send_pointer_event');
    stderr_like { $c->mouse_button({button => 'left', bstate => 1}) } qr/pointer_event.*1 100, 200/, 'mouse_button click works';
    ok $spice->called('send_pointer_event'), 'send_pointer_event was called';
};

subtest 'consoles::SPICE IPC communication' => sub {
    my $mock_socket = Test::MockObject->new;
    my @written;
    $mock_socket->mock(print => sub ($self, $data) { push @written, $data });

    # Mock getline to return mock JSON frames
    my @getlines = (
        "{\"status\":\"ok\"}\n",    # key response
        "{\"status\":\"ok\"}\n",    # mouse response
        "{\"status\":\"ok\",\"width\":1024,\"height\":768,\"size\":12}\n",    # get_frame response
    );
    $mock_socket->mock(getline => sub ($self) { shift @getlines });

    # Mock read to return dummy frame bytes (12 bytes for 2x2 RGB)
    $mock_socket->mock(read => sub {
            $_[1] = "\xff\x00\x00" x 4;    # Red pixels
            return 12;
    });

    my $client = consoles::SPICE->new({hostname => 'localhost', port => 5900});
    $client->socket($mock_socket);

    # Test key event serialization
    @written = ();
    $client->map_and_send_key('28', 1, 0.1);
    ok @written, 'key event sent';
    like $written[0], qr/"cmd":"key_event"/, 'contains cmd key_event';
    like $written[0], qr/"key":"28"/, 'contains key scan code';
    like $written[0], qr/"down":true/, 'contains down true';

    # Test mouse event serialization
    @written = ();
    $client->mouse_move_to(100, 200);
    ok @written, 'mouse event sent';
    like $written[0], qr/"cmd":"mouse_event"/, 'contains cmd mouse_event';
    like $written[0], qr/"x":100/, 'contains x';
    like $written[0], qr/"y":200/, 'contains y';

    # Test framebuffer decoding
    @written = ();
    my $tinycv_mock = Test::MockModule->new('tinycv', no_auto => 1);
    my $from_ppm_called;
    $tinycv_mock->mock(from_ppm => sub ($ppm) {
            $from_ppm_called = 1;
            like $ppm, qr/P6\n1024 768\n255\n/, 'PPM header generated correctly';
            return 'mock_image_object';
    });

    $client->update_framebuffer();
    ok $from_ppm_called, 'tinycv::from_ppm was called';
    is $client->_framebuffer, 'mock_image_object', 'framebuffer successfully decoded and saved';
};



subtest 'spice_base additional methods' => sub {
    my $mock_backend = Test::MockObject->new;
    $mock_backend->set_true('run_capture_loop');
    $c->{backend} = $mock_backend;

    # mouse_absolute
    is $c->mouse_absolute, 1, 'mouse_absolute returns 1';

    # hold_key / release_key
    lives_ok { $c->hold_key({key => 'ctrl'}) } 'hold_key works';
    lives_ok { $c->release_key({key => 'ctrl'}) } 'release_key works';

    # current_screen / request_screen_update
    $spice->set_true('update_framebuffer');
    $spice->mock('_framebuffer' => sub { return 'fake_frame' });
    $c->request_screen_update();
    is $c->current_screen, 'fake_frame', 'current_screen returns frame';

    # missing vnc object
    $c->{vnc} = undef;
    is $c->current_screen, undef, 'current_screen returns undef if no vnc';
    $c->request_screen_update(); # Should just return

    dies_ok { $c->send_key_event('ret', 0.1) } 'send_key_event dies when no vnc';
    dies_ok { $c->hold_key({key => 'ctrl'}) } 'hold_key dies when no vnc';
    dies_ok { $c->release_key({key => 'ctrl'}) } 'release_key dies when no vnc';
    dies_ok { $c->mouse_button({button => 'left', bstate => 1}) } 'mouse_button dies when no vnc';

    # disable
    my $mock_socket = Test::MockObject->new;
    $mock_socket->set_true('close');
    $spice->set_always('socket', $mock_socket);
    $c->{vnc} = $spice;
    $c->disable();
    is $c->{vnc}, undef, 'disable clears vnc';
    
    # connect_remote
    dies_ok { $c->connect_remote({}) } 'connect_remote dies without hostname/port';
    
    my $client_mock = Test::MockModule->new('consoles::SPICE');
    $client_mock->mock('login' => sub { return 1 });
    stderr_like { $c->connect_remote({hostname => 'localhost', port => 5900}) } qr/Establishing SPICE connection/, 'connect_remote creates SPICE object';
    is $c->{vnc}->hostname, 'localhost', 'hostname is set correctly';
};

subtest 'consoles::SPICE map_and_send_key edge cases' => sub {
    my $client = consoles::SPICE->new({hostname => 'localhost', port => 5900});
    my $mock_socket = Test::MockObject->new;
    $mock_socket->set_true('print');
    $mock_socket->set_always('getline', "{\"status\":\"ok\"}\n");
    $client->socket($mock_socket);

    stderr_like { $client->map_and_send_key('unknown_key', 1, 0.1) } qr/Unknown key mapping for SPICE/, 'unknown key warns';
    lives_ok { $client->map_and_send_key('A', 1, 0.1) } 'uppercase letter works';
    lives_ok { $client->map_and_send_key('!', 1, 0.1) } 'shift symbol works';
    lives_ok { $client->map_and_send_key('1-2', undef, 0.1) } 'number works';
    lives_ok { $client->map_and_send_key('a-b', 0, 0.001) } 'multiple keys with small delay';
};
done_testing();

subtest 'consoles::SPICE login/connection' => sub {
    my $client = consoles::SPICE->new({hostname => 'localhost', port => 5900});
    my $io_mock = Test::MockModule->new('IO::Socket::UNIX');
    
    # Touch the fallback socket so -e passes
    system("touch /tmp/spice-bridge.sock");
    
    $io_mock->mock('new' => sub {
        my ($class, %args) = @_;
        if ($args{Peer} =~ /5900/) {
            return undef; # Fail port specific
        } else {
            return Test::MockObject->new->set_true('print')->set_always('getline', "{\"status\":\"ok\"}\n");
        }
    });

    # It will fallback and warn
    stderr_like { $client->login(1) } qr/Falling back to SPICE bridge socket/, 'login falls back to default socket';
    
    # Now test complete failure
    unlink("/tmp/spice-bridge.sock");
    $io_mock->mock('new' => sub { return undef });
    
    # Needs to suppress the sleep to be fast
    my $orig_select = \&CORE::GLOBAL::select;
    # Well, we can't easily mock select. It's just 3 seconds (30 * 0.1) and 1s (10 * 0.1). 4 seconds total.
    dies_ok { stderr_like { $client->login(1) } qr/Falling back/ } 'login dies when no socket available';
};
