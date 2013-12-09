use base "installstep";
use strict;
use bmwqemu;

sub run()
{
 mouse_set(10,10);
 mouse_hide(1);
 sleep 1;
 waitidle(10);
	waitstillimage(20,2000);
if($ENV{PART}=~/lvm/) {
  sendkey "tab"; # select disk drive
  sleep 1;
  sendkey "tab"; # select partitioning solution
  sleep 1;
  sendkey "down"; # select custom
  sleep 1;
  sendkey "tab"; # select help
  sleep 1;
  sendkey "tab"; # select next
  sleep 1;
  sendkey "ret"; # push next
  sleep 1;
  sendkey "tab";
  sleep 1;
  sendkey "tab"; # select empty disk
  sleep 1;
  sendkey "ret"; # open menu on empty disk
  sleep 1;
  sendkey "tab"; # tab past details text (odd that's even tabbable)
  sleep 1;
  sendkey "tab"; # tab to create
  sleep 1;
  sendkey "ret"; # push create
  sleep 1;
  sendkey "tab"; # start sector
  sleep 1;
  sendkey "tab"; # size
  sleep 1;
  sendkey "pgup"; # scroll down
  sleep 1;
  sendkey "pgdn"; # scroll bigger, twice
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "tab"; # select FS type (default)
  sleep 1;
  sendkey "tab"; # select mount point (/)
  sleep 1;
  sendkey "tab"; # select blank  - TODO
  sleep 1;
  sendkey "tab"; # select encrypted 
  sleep 1;
  sendkey "tab"; # select cancel 
  sleep 1;                       
  sendkey "tab"; # select OK
  sleep 1;
  sendkey "ret"; # push OK
  sleep 1;
  sendkey "tab"; # select empty space
  sleep 1;
  sendkey "ret"; # open menu
  sleep 1;
  sendkey "tab"; # details
  sleep 1;
  sendkey "tab"; # create
  sleep 1;
  sendkey "ret"; # push create
  sleep 1;
  sendkey "tab"; # select start
  sleep 1;
  sendkey "tab"; # select size
  sleep 1;
  sendkey "home"; # zero size
  sleep 1;
  sendkey "pgdn"; # inrease size 6 times
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "pgdn";
  sleep 1;
  sendkey "tab"; # select fileystem type
  sleep 1;
  sendkey "end"; # go to bottom of list
  sleep 1;
  sendkey "up"; # go up to LVM
  sleep 1;
  sendkey "tab"; # select encryption
  sleep 1;
  sendkey "tab"; # cancel
  sleep 1;
  sendkey "tab"; # ok
  sleep 1;
  sendkey "ret"; # push ok
  sleep 1;
  sendkey "tab"; # empty space
  sleep 1;
  sendkey "tab"; # details
  sleep 1;
  sendkey "tab"; # resize
  sleep 1;
  sendkey "tab"; # add to lvm
  sleep 1;
  sendkey "ret"; # push add to lvm
  sleep 1;
  sendkey "ret"; # write partition table to disk
  sleep 1;
  waitinststage("mageia-newlvm", 9000);
  sendkey "ret"; # accept default name
  # diag("Handing over for manual testing");
#   sleep 9000;
  sendkey "shift-tab"; # switch to disk tabs
  sleep 1;
  sendkey "shift-tab";
  sleep 1;
  sendkey "shift-tab";
  sleep 1;
  sendkey "shift-tab";
  sleep 1;
  sendkey "left"; # select volume group
  sleep 1;
  sendkey "tab"; # select empty space
  sleep 1;
  sendkey "ret"; # activate empty space menu
  sleep 1;
  sendkey "tab"; # details
  sleep 1;
  sendkey "tab"; # create
  sleep 1;
  sendkey "ret"; # push create button
  sleep 1;
  sendkey "tab";  # select size
  sleep 1;
  sendkey "home"; # zero size
  sleep 1;
  sendkey "pgdn"; # increment size
  sleep 1;
  sendkey "tab"; # select FS type (it will be swap by default)
  sleep 1;
  sendkey "tab"; # select logical volume name
  sleep 1;
  sendkey "tab"; # select BLANK - TODO
  sleep 1;
  sendkey "tab"; # select encrypted
  sleep 1;
  sendkey "tab"; # select cancel
  sleep 1;
  sendkey "tab"; # select OK
  sleep 1;
  sendkey "ret"; # push OK
  sleep 1;
  sendkey "tab"; # select blank
  sleep 1;
  sendkey "ret"; # activate menu
  sleep 1;
  sendkey "tab"; # select details
  sleep 1;
  sendkey "tab"; # select create button
  sleep 1;
  sendkey "ret"; # push button
  sleep 1;
  sendkey "tab"; # select size
  sleep 1;
  sendkey "end"; # use remaining space
  sleep 1;
  sendkey "tab"; # select FS type
  sleep 1;
  sendkey "home"; # start at top of list (swap)
  sleep 1;
  sendkey "down"; # Brtfs
  sleep 1;
  sendkey "down"; # native
  sleep 1;
  sendkey "down"; # ext3
  sleep 1;
  sendkey "down"; # ext4
  sleep 1;
  sendkey "down"; # reiserFS
# BUG, cannot use XFS for /usr
#  sleep 1;
#  sendkey "down"; # XFS
  #JFS
  #FAT32
  #NTFS-3G
  #NTFS
  #Encrypted
  #LVM
  #Linux Raid
  sleep 1;
  sendkey "tab"; # select mount point (default is /usr)
  sleep 1;
  sendkey "tab"; # select BLANK - TOOD
  sleep 1;
  sendkey "tab"; # select LVM name
  sleep 1;
  sendkey "tab"; # select BLANK - TOOD
  sleep 1;
  sendkey "tab"; # select encrypted
  sleep 1;
  sendkey "tab"; # select cancel
  sleep 1;
  sendkey "tab"; # select OK
  sleep 1;
  sendkey "ret"; # Push OK, after creating /usr
  sleep 10;
  sendkey "tab"; # select details
  sleep 1;
  sendkey "tab"; # select mount point
  sleep 1;
  sendkey "tab"; # select resize
  sleep 1;
  sendkey "tab"; # select delete
  sleep 1;
  sendkey "tab"; # select clear all
  sleep 1;
  sendkey "tab"; # select auto-allocate
  sleep 1;
  sendkey "tab"; # select toggle expert mode
  sleep 1;
  sendkey "tab"; # select help
  sleep 1;
  sendkey "tab"; # select more
  sleep 1;
  sendkey "tab"; # select done
  sleep 1;
  sendkey "ret"; # push done

} else { 
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # help
        sendkey "tab"; # next button
	sendkey "ret"; # push next
}

}

1;
