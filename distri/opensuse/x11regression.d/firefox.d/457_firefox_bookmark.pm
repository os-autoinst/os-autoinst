# auther xjin
use base "basetest";
use bmwqemu;

sub run()
{
  my $self=shift;
  mouse_hide(1);

# to clear all of previous settings and then open the app
  x11_start_program("rm -rf .mozilla");
  x11_start_program("pkill -9 firefox");
  x11_start_program("firefox"); sleep 10;

# first confirm www.baidu.com has not been bookmarked yet.
  sendkey "ctrl-shift-o"; sleep 1; 
  sendkey "tab"; sleep 1;
  sendkey "tab"; sleep 1;
  sendautotype "www.baidu.com";
  sendkey "ret"; sleep 3;

  checkneedle("bookmark-not-yet",2);
  sendkey "alt-f4";

# bookmark the page
  sendkey "ctrl-l";
  sendautotype "www.baidu.com"; sleep 1;
  sendkey "ret"; sleep 6;
  checkneedle("bookmark-baidu-main",3);

  sendkey "ctrl-d"; sleep 2;
  checkneedle("bookmarking",3);
  sendkey "ret"; sleep 2;

# check all bookmarked page and open baidu mainpage in a new tab
  sendkey "ctrl-t"; sleep 1;
  sendkey "ctrl-shift-o"; sleep 1;

## check toolbar menu and unsorted section displayed; and baidu mainpage in menu section
  checkneedle("bookmark-all-bookmark-menu",3);
  sendkey "down"; sleep 1;
  sendkey "ret";
  checkneedle("bookmark-baidu-under-bookmark-menu",3);

## open baidu page
  sendkey "tab";
  sendkey "tab";
  sendkey "tab";
  sendautotype "www.baidu.com";
  sendkey "ret";
  sendkey "ret";
  sendkey "tab";
  sendkey "tab";
  sendkey "ret"; sleep 2;

  checkneedle("bookmark-baidu-main",2);

# close the bookmark lib page and then close firefox
  sendkey "alt-tab"; sleep 2;
  sendkey "alt-f4"; sleep 5;
  checkneedle("bookmark-menu-closed",3);

## close firefox
  sendkey "alt-f4"; sleep 1;
  sendkey "ret";  
}

1;
