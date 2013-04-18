#!/usr/bin/perl -cw
# 
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
$o = {
       'timezone' => {
		       'ntp' => undef,
		       'timezone' => 'Pacific/Auckland',
		       'UTC' => 1
		     },
       'security_user' => undef,
       'default_packages' => [
			       'libalsa-data',
			       'mandi-ifw',
			       'mageia-gfxboot-theme',
			       'dhcp-client',
			       'pm-utils',
			       'oxygen-gtk3',
			       'vim-enhanced',
			       'basesystem',
			       'acpid',
			       'tmpwatch',
			       'strace',
			       'plymouth-scripts',
			       'coreutils-doc',
			       'locales-en',
			       'sharutils',
			       'acpi',
			       'shorewall',
			       'perl-Hal-Cdroms',
			       'at-spi2-core',
			       'xdg-user-dirs-gtk',
			       'suspend',
			       'oxygen-icon-theme',
			       'lib64gvfscommon0',
			       'lsof',
			       'ldetect',
			       'info',
			       'man-pages',
			       'harddrake',
			       'hdparm',
			       'lftp',
			       'grub',
			       'drakx-net-text',
			       'cronie-anacron',
			       'kernel-desktop-latest',
			       'lib64openssl-engines1.0.0',
			       'tree',
			       'sudo',
			       'hexedit',
			       'numlock',
			       'procmail',
			       'curl',
			       'gnome-keyring',
			       'nss_mdns',
			       'microcode_ctl',
			       'bc',
			       'iwlwifi-agn-ucode',
			       'rtlwifi-firmware',
			       'kernel-firmware-nonfree',
			       'radeon-firmware',
			       'microcode',
			       'ralink-firmware'
			     ],
       'users' => [
		    {
		      'icon' => 'default',
		      'uid' => undef,
		      'name' => 'bernhard',
		      'realname' => 'Bernhard M. Wiedemann',
		      'groups' => [],
		      'shell' => '/bin/bash',
		      'gid' => undef
		    }
		  ],
       'locale' => {
		     'country' => 'NZ',
		     'IM' => undef,
		     'lang' => 'en_NZ',
		     'langs' => {
				  'en_NZ' => 1
				},
		     'utf8' => 1
		   },
       'net' => {
		  'zeroconf' => {},
		  'network' => {
				 'NETWORKING' => 'yes',
				 'CRDA_DOMAIN' => 'NZ'
			       },
		  'resolv' => {
				'DOMAINNAME' => undef,
				'dnsServer' => undef,
				'DOMAINNAME2' => undef,
				'dnsServer2' => undef,
				'DOMAINNAME3' => undef,
				'dnsServer3' => undef
			      },
		  'wireless' => {},
		  'ethernet' => {},
		  'ifcfg' => {
			       'eth0' => {
					   'BOOTPROTO' => 'dhcp',
					   'HWADDR' => undef,
					   'DEVICE' => 'eth0',
					   'NETMASK' => '255.255.255.0',
					   'BROADCAST' => '',
					   'NETWORK' => '',
					   'ONBOOT' => 'yes',
					   'METRIC' => 10
					 }
			     },
		  'net_interface' => 'eth0',
		  'type' => 'ethernet',
		  'PROFILE' => 'default'
		},
       'authentication' => {
			     'shadow' => 1,
			     'blowfish' => 1
			   },
       'partitions' => [
			 {
			   'fs_type' => 'ext4',
			   'mntpoint' => '/',
			   'size' => 16775104
			 },
			 {
			   'fs_type' => 'swap',
			   'mntpoint' => 'swap',
			   'size' => 8188960
			 }
		       ],
       'partitioning' => {
			   'auto_allocate' => '1',
			   'clearall' => 1,
			   'eraseBadPartitions' => 0
			 },
       'superuser' => {
			'pw' => '$2a$08$fq8B.YUdWPHslcz1j0G6hOB8jX5s.z7d5zjV3vTFmHzgTC9NlcAx2',
			'uid' => '0',
			'realname' => 'root',
			'shell' => '/bin/bash',
			'home' => '/root',
			'gid' => '0'
		      },
       'security' => 1,
       'mouse' => {
		    'EmulateWheel' => undef,
		    'synaptics' => undef,
		    'name' => 'Any PS/2 & USB mice',
		    'device' => 'input/mice',
		    'evdev_mice' => [
				      {
					'device' => '/dev/input/by-id/usb--event-mouse',
					'HWheelRelativeAxisButtons' => '7 6'
				      }
				    ],
		    'evdev_mice_all' => [
					  {
					    'device' => '/dev/input/by-id/usb--event-mouse',
					    'HWheelRelativeAxisButtons' => '7 6'
					  },
					  {
					    'device' => '/dev/input/by-id/usb--event-mouse',
					    'HWheelRelativeAxisButtons' => '7 6'
					  }
					],
		    'type' => 'Universal',
		    'nbuttons' => 7,
		    'Protocol' => 'ExplorerPS/2',
		    'wacom' => [],
		    'MOUSETYPE' => 'ps/2'
		  },
       'interactiveSteps' => [
			     ],
       'autoExitInstall' => '',
       'keyboard' => {
		       'GRP_TOGGLE' => '',
		       'KEYBOARD' => 'us'
		     }
     };
