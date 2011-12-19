use base "basetest";
use strict;
use bmwqemu;

sub is_applicable
{
        return $ENV{SID}
}

sub run()
{
        my $self=shift;
        sendkey "ctrl-alt-f4"; sleep 3;
        sendautotype "root\n";
        waitidle;
        sleep 2;
        sendpassword; sendautotype "\n";
        sleep 3;
        $self->take_screenshot; sleep 2;
        if($ENV{HTTPPROXY}) {
                #already in apt.conf #sendautotype "export http_proxy=http://$ENV{HTTPPROXY}/\n"; # proxy
        }
        script_run("vi /etc/apt/sources.list");
        sendautotype ":%s/wheezy/sid/\n";sleep 3;
        sendautotype ":wq\n";
        script_run "aptitude update";
        waitstillimage;
        #script_run "PAGER=cat aptitude -y upgrade";
        #waitstillimage(45,1200);
        script_run "PAGER=cat aptitude -y dist-upgrade";
        {
                local $ENV{SCREENSHOTINTERVAL}=5;
                waitstillimage(45,1200);
        }
        $self->take_screenshot; sleep 2;
        sendkey "ctrl-alt-delete";
        waitstillimage(12,100); # wait until reboot finished
}

1;
