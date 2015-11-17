elsif ($backend_console =~ qr/ssh(-X)?(-xterm_vt)?/) {


    
my $host        = get_var("PARMFILE")->{Hostname};
        my $sshpassword = get_var("PARMFILE")->{sshpassword};
        system("ssh-keygen -R $host -f ./known_hosts");
        my $sshcommand = "ssh";
        my $display_id = get_var("VNC") || die "VNC unset in vars.json.";
        my $display    = ":" . $display_id;
        if ($backend_console eq "ssh-X") {
            $sshcommand = "DISPLAY=$display " . $sshcommand . " -X";
        }
        $sshcommand .= " -o UserKnownHostsFile=./known_hosts -o StrictHostKeyChecking=no root\@$host";
        my $term_app = ($backend_console =~ qr/-xterm_vt/) ? "xterm" : "x3270";
        if ($term_app eq "x3270") {
            $sshcommand = "TERM=vt100 " . $sshcommand;
            $console_info = $self->new_3270_console({vnc_backend => $self});
            # do ssh connect
            my $s3270 = $console_info->{console};
            $s3270->send_3270("Connect(\"-e $sshcommand\")");
            # wait for 10 seconds for password prompt
            for my $i (-9 .. 0) {
                $s3270->send_3270("Snap");
                my $r  = $s3270->send_3270("Snap(Ascii)");
                my $co = $r->{command_output};
                # CORE::say bmwqemu::pp($r);
                CORE::say bmwqemu::pp($co);
                last if grep { /[Pp]assword:/ } @$co;
                die "ssh password prompt timout connecting to $host" unless $i;
                sleep 1;
            }
            $s3270->send_3270("String(\"$sshpassword\")");
            $s3270->send_3270("ENTER");
	     }
        else {
            $sshcommand = "TERM=xterm " . $sshcommand;
            my $xterm_vt_cmd = "xterm-console";
            my $window_name  = "ssh:$testapi_console";
            system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$sshcommand' & echo \$!") != -1 ||    #
              die "cant' start xterm on $display (err: $! retval: $?)";
            my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
            chomp($window_id);

            $console_info->{window_id} = $window_id;
            $console_info->{vnc}       = $self->{consoles}->{worker}->{vnc};
            $console_info->{console}   = $self->{consoles}->{worker}->{vnc};
            $console_info->{DISPLAY}   = $display;
            # FIXME: capture xterm output, wait for "password:" prompt
            # possible tactics:
            # -xrm bind key print-immediate() action to some cryptic unused key combination like ctrl-alt-§
            # -xrm printerCommand: cat  or simply true
            # xdotool key ctrl-alt-§ and examine file XTerm-$TIMESTAMP (changing filename!)
            sleep 2;
            die if $sshpassword =~ /'/;
            #xterm does not accept key events by default, for security reasons, so this won't work:
            #system("DISPLAY=$display xdotool type '$sshpassword' key enter");
            die unless $console_info->{console} == $self->{vnc};
            $self->type_string({text => "$sshpassword\n"});
        }


sub disable
    elsif ($backend_console =~ qr/ssh(-X)?(-xterm_vt)?/) {
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }

sub select() {
    my ($self) = @_;
    $self->_activate_window();
}
