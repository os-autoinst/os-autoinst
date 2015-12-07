import perl
perl.use("registration")

def run(self):
    print "This python code ran"
    #perl.assert_screen("fooweiuhfiu", 1) # to test how it dies
    if perl.get_var("USBBOOT"):
        perl.assert_screen("boot-menu", 1)
        perl.send_key("f12")
        perl.assert_screen("boot-menu-usb", 4)
        perl.send_key(2 + perl.get_var("NUMDISKS"))
    perl.assert_screen("inst-bootmenu", 15)
    perl.send_key_until_needlematch('inst-oninstallation', 'down', 10, 5)
    perl.registration.registration_bootloader_params()
    perl.type_string("qwertyuiopasdfghjkl")
    print "TODO: more code"
    perl.send_key('ret')

def test_flags(self):
    return dict([("fatal", 1)])

