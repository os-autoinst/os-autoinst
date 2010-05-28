script_sudo "/sbin/yast2 lan";
sendkey "alt-c"; # cancel yast2 lan
script_run 'echo $?';

1;
