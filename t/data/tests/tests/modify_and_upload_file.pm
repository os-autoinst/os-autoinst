# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use base "basetest";
use testapi;

my $orig_file = <<'END';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE profile>
<profile xmlns="http://www.suse.com/1.0/yast2ns" xmlns:config="http://www.suse.com/1.0/configns">
<users config:type="list">
    <user>
      <encrypted config:type="boolean">false</encrypted>
      <user_password>PASSWORD</user_password>
      <username>root</username>
    </user>
  </users>
</profile>
END

sub run {
    # Get file from data directory
    my $content = get_test_data('autoinst.xml');

    if ($content eq $orig_file) {
        type_string("echo get_test_data returned expected file\n");
    }
    my $url = autoinst_url . '/files/modified.xml';
    $content =~ s/PASSWORD/nots3cr3t/g;
    save_tmp_file('modified.xml', $content);
    # Verify that correct file is downloaded
    assert_script_run("wget -q $url");
    script_run "echo '72d2c15cb10535f36862d7d2eecc8a79  modified.xml' > modified.md5";
    assert_script_run("md5sum -c modified.md5");

    type_string("echo save_tmp_file returned expected file\n");
}
