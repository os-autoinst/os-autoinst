use base "basetest";
use strict;
use bmwqemu;
use Time::HiRes qw(sleep);

sub run()
{
	if($ENV{ZDUP} || $ENV{WDUP}) {
		qemusend "eject -f ide1-cd0";
		qemusend "system_reset";
		sleep 10;
		sendkey "ret"; # boot
		return;
	}

if($ENV{MEMTEST}) { # special
	# only run this one
	for(1..6) {
		sendkey "down";
	}
	sleep 3;
	sendkey "ret";
	sleep 6000;
	exit 0; # done
}
# assume bios+grub+anim already waited in start.sh
if(!$ENV{LIVETEST}) {
	# installation (instead of HDDboot on non-live)
	# installation (instead of live):
	sendkey "down";
	if($ENV{PROMO}) {
		# has extra GNOME-Live and KDE-Live menu entries
		for(1..2) {sendkey "down";}
	}
} else {
	if($ENV{PROMO}) {
		for(1..2) {sendkey "down";} # select KDE Live
	}
}

# 1024x768
if($ENV{RES1024}) { # default is 800x600
	sendkey "f3";
	sendkey "down";
	sendkey "ret";
}

sendautotype("nohz=off "); # NOHZ caused errors with 2.6.26
if(!$ENV{NICEVIDEO}) {
	sleep 15; sendautotype("console=ttyS0 "); # to get crash dumps as text
	sleep 15; sendautotype("console=tty "); # to get crash dumps as text
	my $e=$ENV{EXTRABOOTPARAMS};
	if($e) {sleep 10;sendautotype("$e ");}
	sleep 10; # workaround slow gfxboot drawing 662991
}
#sendautotype("kiwidebug=1 ");

# set HTTP-source to not use factory-snapshot
if($ENV{NETBOOT}) {
	sendkey "f4";
	sendkey "ret";
	my $mirroraddr="";
	my $mirrorpath="/factory";
	if($ENV{SUSEMIRROR} && $ENV{SUSEMIRROR}=~m{^([a-zA-Z0-9.-]*)(/.*)$}) {
		($mirroraddr,$mirrorpath)=($1,$2);
	}
        #download.opensuse.org
        if($mirroraddr) {
                for(1..22) { sendkey "backspace" }
                sendautotype($mirroraddr);
        }
	sendkey "tab";
	# change dir
	# leave /repo/oss/ (10 chars)
	for(1..10) { sendkey "left"; }
	for(1..22) { sendkey "backspace"; }
	sendautotype($mirrorpath);

        sleep(2);
	sendkey "ret";

	# HTTP-proxy
	if($ENV{HTTPPROXY} && $ENV{HTTPPROXY}=~m/([0-9.]+):(\d+)/) {
		my($proxyhost,$proxyport)=($1,$2);
		sendkey "f4";
		for(1..4) {
			sendkey "down";
		}
		sendkey "ret";
		sendautotype("$proxyhost\t$proxyport\n");
		sleep(1.5);

		# add boot parameters
		# ZYPP... enables proxy caching
	}
	sendautotype("ZYPP_ARIA2C=0 ZYPP_MULTICURL=0 "); sleep 2;
}


# set language last so that above typing will not depend on keyboard layout
if($ENV{INSTLANG}) {
# positions in isolinux language selection ; order matters
# from cpio -i --to-stdout languages < /mnt/boot/*/loader/bootlogo
my @isolinuxlangmap=qw(
af_ZA
ar_EG
ast_ES
bn_BD
bs_BA
bg_BG
ca_ES
cs_CZ
cy_GB
da_DK
de_DE
et_EE
en_GB
en_US
es_ES
fa_IR
fr_FR
gl_ES
ka_GE
gu_IN
el_GR
hi_IN
id_ID
hr_HR
it_IT
he_IL
ja_JP
jv_ID
km_KH
ko_KR
ky_KG
lo_LA
lt_LT
mr_IN
hu_HU
mk_MK
nl_NL
nb_NO
nn_NO
pl_PL
pt_PT
pt_BR
pa_IN
ro_RO
ru_RU
zh_CN
si_LK
sk_SK
sl_SI
sr_RS
fi_FI
sv_SE
tg_TJ
ta_IN
th_TH
vi_VN
zh_TW
tr_TR
uk_UA
wa_BE
xh_ZA
zu_ZA
);
	my $n;
	my %isolinuxlangmap=map {lc($_)=>$n++} @isolinuxlangmap;
	$n=$isolinuxlangmap{lc($ENV{INSTLANG})};
	my $en_us=$isolinuxlangmap{en_us};
	if($n && $n !=$en_us) {
		$n-=$en_us;
		sendkey "f2";
		for(1..abs($n)) {
			sendkey ($n<0?"up":"down");
		}
		sleep 2;
		sendkey "ret";
	}
}

# boot
sendkey "ret";
}

1;
