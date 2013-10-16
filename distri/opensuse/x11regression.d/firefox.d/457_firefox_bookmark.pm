# auther xjin
use base "basetest";
use bmwqemu;

sub run()
{
  my $self=shift;
  mouse_hide(1);
  x11_start_program("firefox"); sleep 10;

# first confirm www.baidu.com has not been bookmarked yet.
  sendkey "ctrl-shift-o"; sleep 1; 
  sendkey "tab"; sleep 1;
  sendkey "tab"; sleep 1;
  sendautotype "www.baidu.com";
  sendkey "ret"; sleep 3;

  waitforneedle("not-bookmark-yet",2);
  sendkey "alt-f4";

# bookmark the page
  sendkey "ctrl-l";
  sendautotype "www.baidu.com"; sleep 1;
  sendkey "ret"; sleep 6;
  waitforneedle("mainpage-baidu",3);

  sendkey "ctrl-d"; sleep 2;
  waitforneedle("bookmarking",3);
  sendkey "ret"; sleep 2;

# check all bookmarked page and open baidu mainpage in a new tab
  sendkey "ctrl-t"; sleep 1;
  sendkey "ctrl-shift-o"; sleep 1;

## check toolbar menu and unsorted section displayed; and baidu mainpage in menu section
  waitforneedle("all-bookmark-menu",3);
  sendkey "down"; sleep 1;
  sendkey "ret";
  waitforneedle("baidu-under-bookmark-menu",3);

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

  waitforneedle("mainpage-baidu",2);

# close the bookmark lib page and then close firefox
  sendkey "alt-tab"; sleep 2;
  sendkey "alt-f4"; sleep 5;
  waitforneedle("bookmark-closed-after",3);

## close firefox
  sendkey "alt-f4"; sleep 1;
  sendkey "ret";  
}

1;
