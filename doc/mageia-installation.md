# Glen Ogilvie - nelg@mageia.org
# December 2013


======= NOTE THAT THIS DOCUMENT IS OUTDATED AND REFERS TO V1 =========

The automated installer here has been tested for Mageia 3 and Mageia 4,
with more work going into Mageia 4.


# For this to work on Mageia 2/3
## KVM

Ensure that libvirtd is running, and that you have hardware support for libvirtd.
Set the permissions on /dev/kvm for the user you are running the test under, for example:

```bash
  setfacl -m "user:test:rw" /dev/kvm
  su - test
  cd tmp
  ../os-autoinst/tools/isotovideo Mageia-3-beta4-x86_64-DVD.iso
```

Provided that os-autoinst is in ~test/ and the iso is in ~test/tmp/

### Required RPMs
```bash
  urpmi swig perl-Data-Dump
  urpmi perl-devel
  urpmi ffmpeg2theora
  urpmi tigervnc
  urpmi perl-Inline
  urpmi mtools

```
#### Mageia 3 (Optional, for openvc support)
```bash
  urpmi opencv-devel
  urpmi lib64opencv_nonfree
```
## env
This instructions assumes you are going to use a user on your system called test,
and that you have your hypervisor setup, see above:

0.  Switch to your test user:
    `su - test`
1.  Download os-autoinst, using git:
    `git clone git://github.com/nelg/os-autoinst.git`
2.  Compile:

```bash
  ./autogen.sh
  ./configure --with-opencv
  make
```

3.  Download, or place a copy of Mageia-3-beta4-x86_64-DVD.iso or simular into ~test/tmp
    `cd ~/tmp
    wget ..`
4.  Ensure you have at least 8gb free disk space.
    `df -h`
5.  Copy the enviroment file to ~/tmp
```bash
    cd ~/tmp
    cp ~/os-autoinst/env-mageia3.sh.sample env.sh
    vi env.sh
``` 
    (See comments within file)

6.  Run the test
    `../os-autoinst/tools/isotovideo Mageia-3-beta4-x86_64-DVD.iso`

## watching the test
To watch the test, use
  `vncviewer -PreferredEncoding=raw localhost:99`

Note, the -PreferredEncoding=raw flag is really important.  Without this, your CPU usage will rocket up and the wait_idle tests will generally fail, which will tend to cause the automated install to not work very well.


To watch after the test has run, use:
  `mplayer video/Mageia-3-beta4-x86_64-DVD.ogv`
You can step through individual frames after pausing it, using the . key.

## Editing the tests
Tests can be edited by editing ~/os-autoinst/distri/mageia/inst.d/
Also, general behaviour of the tests can be changed by editing env.sh, where the tests support it.  Currently, read the source to find out.

- - -

# Testing Mageia 4
This is currently capable of installing Mageia 4 from Mageia-4-RC-x86_64-DVD.iso,
with the following variations, as set in env.sh

KDE, Gnome or no desktop, LVM or non-LVM based partitioning.

At 28 Dec 2013, there is a bug in the installer that sometimes will
cause the installer to mis-align, in which case the test will fail, as it
can't match what it expects to find. 

Currently it relies on recognising certain parts of the install screen,
using md5sum's.  This is unreliable, but needed because things in the installer
change depending on factors like disk size, and the automated installer
needs to push the right buttons. The final output will always have the word fail in it. 
To check, look at the video, and see if serail0 file ends up with "010_consoletest_setup OK" in it.

If your computer is powerful enough, you can run multiple install tests at the 
same time.  

To get stated with testing Mageia4, do the following:
```bash
  su - test
  git clone git://github.com/nelg/os-autoinst.git
  cd os-autoinst; ./autogen.sh; ./configure --with-opencv; make; cd ..
  mkdir -p ~/tmp/test{1..2}
  cp ~/os-autoinst/env-mageia4.sh.sample1 ~/tmp/test1/env.sh 
  cp ~/os-autoinst/env-mageia4.sh.sample2 ~/tmp/test2/env.sh 
  rsync / wget Mageia ISO.
  ln Mageia-4-RC-x86_64-DVD.iso ~/tmp/test1/
  ln Mageia-4-RC-x86_64-DVD.iso ~/tmp/test2/
```

Window 1
```bash
  cd ~/tmp/test1/
  ~/os-autoinst/tools/isotovideo Mageia-4-RC-x86_64-DVD.iso
```
Window 2
```bash
  cd ~/tmp/test1/
  ~/os-autoinst/tools/isotovideo Mageia-4-RC-x86_64-DVD.iso
```

Viewing (careful with your mouse):
```bash
  vncviewer -PreferredEncoding=raw localhost:98
  vncviewer -PreferredEncoding=raw localhost:99
```

Screenshot viewing (preferred):
  Turn on previews and use dolphin to view ~/tmp/test1/qemuscreenshot and ~/tmp/test2/qemuscreenshot


