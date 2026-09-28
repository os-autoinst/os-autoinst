# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::VMWare;

use Mojo::Base -base, -signatures;
use Feature::Compat::Try;
use Mojo::JSON qw(encode_json);
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::Util qw(xml_escape);
use Carp 'croak';
use File::Basename;

use bmwqemu;
use log;

has protocol => 'https';
has host => undef;
has vm_id => undef;
has username => 'root';
has password => undef;
has dewebsockify_pid => undef;

sub _get_vmware_error ($dom) {
    my $faultstring_element = $dom->find('faultstring')->first;
    return $faultstring_element ? $faultstring_element->text : '';
}

sub _prepare_vmware_request ($ua, $api_url, $xml) {
    my $txn = $ua->build_tx(POST => $api_url);
    my $headers = $txn->req->headers;
    $txn->req->body($xml);
    $headers->header(SOAPAction => 'urn:vim25/7.0.2.0');
    $headers->content_type('text/xml');
    $headers->content_length(length $xml);
    return ($txn, $headers);
}

sub configure_from_url ($self, $url) {
    $url = Mojo::URL->new($url);
    $self->protocol($url->protocol)->host($url->host);
    $self->username($url->username)->password($url->password);
    $self->vm_id(substr $url->path, 1) if length $url->path > 1;
}

sub get_vmware_wss_url ($self) {

    # make XML for requests
    my $protocol = $self->protocol or die "No protocol specified\n";
    my $host = $self->host or die "No VMWare host specified\n";
    my $api_url = "$protocol://$host/sdk";
    my $username = xml_escape $self->username;
    my $password = xml_escape $self->password;
    my $vm_id = xml_escape($self->vm_id || $bmwqemu::vars{VIRSH_VM_ID});
    my $auth_xml = qq{<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Header><operationID>esxui-8fb8</operationID></Header><Body><Login xmlns="urn:vim25"><_this type="SessionManager">ha-sessionmgr</_this><userName>$username</userName><password>$password</password></Login></Body></Envelope>};
    my $request_wss_xml = qq{<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Header><operationID>esxui-c51d</operationID></Header><Body><AcquireTicket xmlns="urn:vim25"><_this type="VirtualMachine">$vm_id</_this><ticketType>webmks</ticketType></AcquireTicket></Body></Envelope>};

    # request VMWare session
    my $ua = ($self->{_vmware_ua} //= Mojo::UserAgent->new);
    $ua->cookie_jar->empty;    # avoid auth error because we're already logged in
    my ($auth_txn, $auth_headers) = _prepare_vmware_request($ua, $api_url, $auth_xml);
    $auth_headers->cookie('vmware_client=VMware');
    $ua->insecure($bmwqemu::vars{VMWARE_VNC_OVER_WS_INSECURE} // 0);
    $ua->start($auth_txn);

    # check for auth error
    my $auth_error = _get_vmware_error($auth_txn->result->dom);
    die "VMWare auth request failed: $auth_error\n" if $auth_error;

    # request web socket URL
    my ($request_wss_txn) = _prepare_vmware_request($ua, $api_url, $request_wss_xml);
    $ua->start($request_wss_txn);

    # read web socket URL
    my $res = $request_wss_txn->result;
    my $wss_dom = $res->dom;
    my $url_error = _get_vmware_error($wss_dom);
    die "VMWare web socket URL request failed: $url_error\n" if $url_error;
    my $wss_url = $wss_dom->find('url')->first;
    die "VMWare did not return a web socket URL, it responsed:\n" . $res->body unless $wss_url && $wss_url->text;
    my $cookie = $request_wss_txn->req->cookies->[0];
    die "VMWare did not return a session cookie\n" unless $cookie;
    return (Mojo::URL->new($wss_url->text), $cookie);
}

sub _cleanup_previous_dewebsockify_process ($self) {
    return undef unless my $pid = $self->dewebsockify_pid;
    kill SIGTERM => $pid;
    waitpid $pid, 0;
    $self->dewebsockify_pid(undef);
}

sub _start_dewebsockify_process ($self, $listen_port, $websockets_url, $session, $log_level = undef) {
    my @args = ("$bmwqemu::topdir/script/dewebsockify", '--listenport', $listen_port, '--websocketurl', $websockets_url, '--cookie', "vmware_client=VMware; $session");
    push @args, '--loglevel', $log_level if $log_level;
    push @args, '--insecure' if $bmwqemu::vars{VMWARE_VNC_OVER_WS_INSECURE};
    my $pid = fork;
    return $self->dewebsockify_pid($pid) if $pid;
    exec @args;    # uncoverable statement
}

sub launch_vnc_server ($self, $listen_port) {
    $self->_cleanup_previous_dewebsockify_process;

    my $attempts = $bmwqemu::vars{VMWARE_VNC_OVER_WS_REQUEST_ATTEMPTS} // 11;
    my $delay = $bmwqemu::vars{VMWARE_VNC_OVER_WS_REQUEST_DELAY} // 5;
    my $error;
    for (; $attempts >= 0; --$attempts) {
        my ($websockets_url, $session);
        try { ($websockets_url, $session) = $self->get_vmware_wss_url }
        catch ($e) {
            die $e if $e =~ qr/incorrect user name or password/;    # no use to attempt further
            chomp $e;
            log::diag "$e, trying $attempts more times";
            $error = $e;
            sleep $delay;
            next;
        }
        return $self->_start_dewebsockify_process($listen_port, $websockets_url, $session);
    }
    die $error;
}

sub deduce_url_from_vars ($vnc_console) {
    return undef unless $bmwqemu::vars{VMWARE_VNC_OVER_WS};
    return undef unless ($vnc_console->original_hostname // $vnc_console->hostname) eq ($bmwqemu::vars{VIRSH_GUEST} // '');
    my $host = $bmwqemu::vars{VMWARE_HOST} or die "VMWARE_VNC_OVER_WS set but not VMWARE_HOST\n";
    my $user = $bmwqemu::vars{VMWARE_USERNAME} // 'root';
    my $password = $bmwqemu::vars{VMWARE_PASSWORD} or die "VMWARE_VNC_OVER_WS set but not VMWARE_PASSWORD\n";
    return Mojo::URL->new("https://$host")->userinfo("$user:$password")->to_unsafe_string;
}

sub setup_for_vnc_console ($vnc_console) {
    return undef unless my $ws_url = $vnc_console->vmware_vnc_over_ws_url // deduce_url_from_vars($vnc_console);
    my $self = $vnc_console->{_vmware_handler} //= consoles::VMWare->new;
    log::diag 'Establishing VNC connection over WebSockets via ' . Mojo::URL->new($ws_url)->to_string;
    $vnc_console->original_hostname($vnc_console->hostname) unless $vnc_console->original_hostname;
    $vnc_console->hostname('127.0.0.1');
    $vnc_console->description('VNC over WebSockets server provided by VMWare');
    $self->configure_from_url($ws_url);
    $self->launch_vnc_server($vnc_console->port || 5900);
    return $self;
}


# Provisioning of images into the ESXi datastore via shell scripts run over the SSH
# connection of a consoles::sshVirtsh console ($svirt)

# Indents a shell snippet for interpolation and strips its trailing newline
sub _indent ($script, $level = 0) {
    chomp $script;
    return $script unless $level;
    my $indentation = '    ' x $level;
    $script =~ s/^(?=.)/$indentation/mg;
    return $script;
}

# Sets $vmid to the VM named exactly $name, so openQA-SUT-1 does not match openQA-SUT-10
sub vmid_script ($name) { qq{vmid=\$(vim-cmd vmsvc/getallvms | awk '\$2 == "$name" { print \$1 }')} }

# Path of the temporary copy; contains the VM name so the job's leftover cleanup removes it
sub _tmp_image_path ($dest, $name) { "$dest.$name.part" }

# File telling waiting jobs why this job's copy failed its verification
sub _failure_note_path ($dest, $name) { "$dest.$name.failed" }

# File recording the checksum an image was verified against
sub _verified_record_path ($dest) { "$dest.verified" }

# The expected digest from CHECKSUM_<VAR> for the image named by <VAR>, or undef
sub _expected_checksum ($file_basename) {
    for my $checksum_var (sort grep { /^CHECKSUM_/ } keys %bmwqemu::vars) {
        my $image = $bmwqemu::vars{$checksum_var =~ s/^CHECKSUM_//r};
        next unless defined $image && basename($image) eq $file_basename;
        my $checksum = $bmwqemu::vars{$checksum_var} // next;
        # only a plain digest is safe to interpolate into the shell script
        return lc $checksum if $checksum =~ /^(?:[0-9a-f]{64}|[0-9a-f]{128})$/i;
        bmwqemu::diag "Ignoring $checksum_var, '$checksum' is not a SHA-256 or SHA-512 digest";
    }
    return undef;
}

# Sets $_digest to compare and $_digests to list what was computed in a mismatch message.
# A 64 character checksum is either SHA-256 or SHA-512 truncated, so try SHA-256 first
# and then the other, in the same order as verify_checksum() of the test distribution.
sub _digest_script ($file, $checksum) {
    return <<~"EOF" if length($checksum) == 128;
    _digest=\$(sha512sum "$file" | awk '{print \$1}')
    _digests="SHA-512 \$_digest"
    EOF
    return <<~"EOF";
    _digest=\$(sha256sum "$file" | awk '{print \$1}')
    _digests="SHA-256 \$_digest"
    if [ "\$_digest" != "$checksum" ]; then
        _digest=\$(sha512sum "$file" | awk '{print \$1}' | cut -c1-64)
        _digests="\$_digests, SHA-512 truncated \$_digest"
    fi
    EOF
}

# VMFS has no atomic copy, so copy to a temporary file, verify it and only then rename it
# into place (a metadata operation). Other jobs thus never see a partial or corrupt image,
# and no VM holds a VMFS lock on the temporary file that would block the verification.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _atomic_copy_script ($source, $dest, $tmp, $checksum = undef, $failure_note = undef) {
    my $copy = _replace_notice_script($dest) . <<~"EOF";
    if ! cp "$source" "$tmp"; then
        rm -f "$tmp"
        echo "Unable to copy $source to $dest"
        exit 1
    fi
    EOF
    # waiting jobs fail with the same reason instead of copying the corrupt source again
    my $note = $failure_note ? qq{echo "\$_mismatch" > "$failure_note"} : ':';
    my $verify = !$checksum ? '' : _digest_script($tmp, $checksum) . <<~"EOF";
    if [ "\$_digest" != "$checksum" ]; then
        rm -f "$tmp"
        _mismatch="Checksum mismatch for $source, expected $checksum but computed \$_digests"
        echo "\$_mismatch"
        $note
        exit 1
    fi
    echo "Verified $source against its published checksum"
    EOF
    my $old_record = _verified_record_path($dest);
    my $publish = <<~"EOF" . _record_verified_script($dest, $checksum);
    if ! rm -f "$old_record" || ! mv "$tmp" "$dest"; then
        rm -f "$tmp"
        echo "Unable to publish $dest, it might be held by a running VM"
        exit 1
    fi
    EOF
    return $copy . $verify . $publish . qq{echo "Copied $source to $dest"\n};
}

# Like _atomic_copy_script() but decompressing. The image is recorded with the checksum of
# the compressed asset, as that is what later jobs publish for it.
sub _atomic_decompress_script ($source, $dest, $tmp, $checksum = undef) {
    my $notice = _replace_notice_script($dest);
    my $record = _indent(_record_verified_script($dest, $checksum), 1);
    my $old_record = _verified_record_path($dest);
    return <<~"EOF";
    $notice
    if xz --decompress --stdout "$source" > "$tmp" && rm -f "$old_record" && mv "$tmp" "$dest"; then
    $record
        echo "Decompressed $source to $dest"
    else
        rm -f "$tmp"
        echo "Unable to decompress $source to $dest"
        exit 1
    fi
    EOF
}

# Writes the record; callers remove the old one before the rename so it never vouches
# for new content
sub _record_verified_script ($dest, $checksum = undef) {
    my $record = _verified_record_path($dest);
    return $checksum ? qq{echo "$checksum" > "$record"\n} : '';
}

# Defines _verified(): an existing image counts as present only if its record matches this
# job's checksum. Re-reading the image instead would be slow and fails with "Device or
# resource busy" while another job's VM runs from it.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _verified_script ($checksum = undef) {
    return qq{_verified() { test -e "\$1"; }\n} unless $checksum;
    my $record = _verified_record_path('$1');
    return <<~"EOF";
    _verified() {
        test -e "\$1" || return 1
        test "\$(cat "$record" 2>/dev/null)" = "$checksum"
    }
    EOF
}

# Announces that an unverified image (older, corrupt or republished) gets replaced by a
# verified copy. Replacing heals the datastore without manual cleanup, the log keeps it visible.
sub _replace_notice_script ($dest) {
    return qq{[ ! -e "$dest" ] || echo "Replacing $dest, it is not verified against the published checksum"\n};
}

# Marker directory claimed by the job copying an image
sub _copy_marker_path ($dest) { "$dest.copying" }

# Ensures only one of the jobs arriving together copies an image: the one whose mkdir of
# the marker succeeds sets $_claimed, the others wait for the image to appear.
# - The owner writes a heartbeat, as the temporary file stops growing during verification;
#   a marker whose heartbeat stalls for $stall_timeout seconds is taken over.
# - The marker records its owner, so a job that lost it to a takeover does not remove it.
# - If the owner's copy failed verification, waiters fail too instead of copying again.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _claim_copy_script ($dest, $owner, $checksum = undef, $interval = 10, $stall_timeout = 300) {
    my $marker = _copy_marker_path($dest);
    my $own_note = _failure_note_path($dest, $owner);
    # the owner waited for is only known at runtime, so the path contains the shell variable
    my $waited_note = _failure_note_path($dest, '$_waited_for');
    my $check_waited = !$checksum ? '' : _indent(<<~"EOF", 1);
    _owner=\$(cat "$marker/owner" 2>/dev/null)
    _owner_left=''
    [ -z "\$_waited_for" ] || [ "\$_owner" = "\$_waited_for" ] || _owner_left=1
    if [ -n "\$_owner_left" ] && grep -qF "$checksum" "$waited_note" 2>/dev/null; then
        cat "$waited_note"
        echo "Not copying $dest again, the copy of \$_waited_for failed its verification"
        exit 1
    fi
    [ -z "\$_owner" ] || _waited_for=\$_owner
    EOF
    return <<~"EOF";
    _claimed=''
    _heartbeat_pid=''
    _owns_marker() { test "\$(cat "$marker/owner" 2>/dev/null)" = "$owner"; }
    _heartbeat() {
        _beat=0
        while kill -0 \$\$ 2>/dev/null && _owns_marker; do
            _beat=\$((_beat + 1))
            echo "\$_beat" > "$marker/heartbeat"
            sleep $interval
        done
    }
    _release_claim() {
        if [ -n "\$_heartbeat_pid" ]; then
            { kill "\$_heartbeat_pid"; wait "\$_heartbeat_pid"; } 2>/dev/null
        fi
        if [ -n "\$_claimed" ] && _owns_marker; then
            rm -rf "$marker"
        fi
    }
    trap _release_claim EXIT
    _seen=''
    _stalled=0
    _waited_for=''
    until _verified "$dest"; do
    $check_waited
        if mkdir "$marker" 2>/dev/null; then
            echo "$owner" > "$marker/owner"
            rm -f "$own_note"
            _claimed=1
            _heartbeat > /dev/null 2>&1 &
            _heartbeat_pid=\$!
            break
        fi
        _marker_state=\$(cat "$marker/owner" "$marker/heartbeat" 2>/dev/null)
        if [ "\$_marker_state" != "\$_seen" ]; then
            _seen=\$_marker_state
            _stalled=0
        else
            _stalled=\$((_stalled + $interval))
        fi
        if [ "\$_stalled" -ge $stall_timeout ]; then
            echo "No heartbeat from the job copying $dest for ${stall_timeout}s, taking the copy over"
            rm -rf "$marker"
            _stalled=0
            continue
        fi
        echo "Waiting for another job to copy $dest"
        sleep $interval
    done
    EOF
}

# Verifies that vmware image is present in the host datastore, otherwise copies from input.
sub provide_image_in_datastore ($svirt, $input_file, $vmware_openqa_datastore, %args) {
    my $nfs_dir = ($args{backingfile}) ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    my $debug = ($bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} // 0) ? 'set -x;' : '';
    my $base_dir = $bmwqemu::vars{VIRSH_OPENQA_BASEDIR} // '/vmfs/volumes';
    my $basefile = basename($input_file);
    # expected name of uncompressed image
    my $baseimage = basename($input_file) =~ s/\.xz$//r;
    my $dest_image = "$vmware_openqa_datastore/${baseimage}";
    # Use the standard folder for an input file without full path
    my $file_origin = ($input_file eq $basefile) ? "$base_dir/$vmware_nfs_datastore/$nfs_dir/$basefile" : $input_file;
    my $dest_xz = "$dest_image.xz";
    my $name = $svirt->name;
    # the checksum belongs to the asset as named in the job, possibly the .xz file
    my $checksum = _expected_checksum($basefile);
    # check image is present and verified; copy and decompression are atomic. Claiming the
    # final image also covers the .xz copy, as only the job producing the image needs it.
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
    my $verified = _indent(_verified_script($checksum));
    my $claim = _indent(_claim_copy_script($dest_image, $name, $checksum));
    my $failure_note = _failure_note_path($dest_image, $name);
    my $copy_xz = _indent(_atomic_copy_script($file_origin, $dest_xz, _tmp_image_path($dest_xz, $name), $checksum, $failure_note), 3);
    my $decompress = _indent(_atomic_decompress_script($dest_xz, $dest_image, _tmp_image_path($dest_image, $name), $checksum), 2);
    my $copy_image = _indent(_atomic_copy_script($file_origin, $dest_image, _tmp_image_path($dest_image, $name), $checksum, $failure_note), 2);
    my $cmd = <<~"EOF";
    $debug
    input_file="$input_file"
    $verified
    $claim
    if _verified "$dest_image"; then
        echo "VMware image $dest_image ready"
    else
        if [ "\${input_file##*.}" = "xz" ]; then
            if ! _verified "$dest_xz"; then
    $copy_xz
            fi
    $decompress
        else
    $copy_image
        fi
    fi
    echo "Done: origin:" $file_origin* " ; dest.:" $dest_image*
    EOF

    my $ret = $svirt->run_cmd($cmd, domain => 'sshVMwareServer');
    croak "Error on VMware image $input_file preparation." if $ret;
    return $dest_image;
}

sub copy_image_to_datastore ($svirt, $name, $backingfile, $file_basename, %args) {
    my $vmware_openqa_datastore = $args{vmware_openqa_datastore};
    my $vmware_disk_path = $args{vmware_disk_path};
    my $vmware_disk_path_thinfile = $args{vmware_disk_path_thinfile};
    my $copy_timeout = $args{copy_timeout} // 600;

    # Copy the image from the NFS datastore unless it is already present and verified
    my $nfs_dir = $backingfile ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    # cmd debugging activable by setting VMWARE_NFS_DATASTORE_DEBUG=1
    my $ds_debug = ($bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} // 0) ? 'set -x;' : '';
    my $dest_image = "$vmware_openqa_datastore$file_basename";
    my $file_origin = "/vmfs/volumes/$vmware_nfs_datastore/$nfs_dir/$file_basename";
    my $checksum = _expected_checksum($file_basename);
    my $verified = _indent(_verified_script($checksum));
    my $claim = _indent(_claim_copy_script($dest_image, $name, $checksum));
    my $copy_image = _indent(_atomic_copy_script($file_origin, $dest_image, _tmp_image_path($dest_image, $name), $checksum, _failure_note_path($dest_image, $name)), 1);
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
    my $cmd = <<~"EOF";
    $ds_debug
    $verified
    $claim
    if _verified "$dest_image"; then
        echo "VMware image $dest_image is already present and verified"
    else
    $copy_image
    fi
    EOF
    my $retval = $svirt->run_cmd($cmd, domain => 'sshVMwareServer', timeout => $copy_timeout);
    die "Can't copy VMware image $file_basename" if $retval;
    return unless $backingfile;
    # Power VM off, delete its disk image, and create it again.
    # Then wait for some time for the VM to *really* turn off.
    $cmd =
      '( set -x; ' . vmid_script($name) . ';' .
      'if [ $vmid ]; then ' .
      'vim-cmd vmsvc/power.off $vmid;' .
      'fi;' .
      "vmkfstools -v1 -U $vmware_disk_path_thinfile;" .
      "vmkfstools -v1 -i $vmware_disk_path --diskformat thin $vmware_disk_path_thinfile; sleep 10 ) 2>&1";
    $retval = $svirt->run_cmd($cmd, domain => 'sshVMwareServer');
    die q{Can't create thin VMware image} if $retval;
}

1;
