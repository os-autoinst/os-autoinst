package utils;

use strict;

use bmwqemu qw(diag fctwarn);
use base 'Exporter';
use Exporter;
use testapi;
use Encode;

our @EXPORT = qw/replace_special_char/;

#
# cette focntion à pour objectif de remplacer les caractères problématiques
# par leur code keysym afin de pallier les erreur d'affichage
sub replace_special_char {
  my $chaine = shift;
  
  #233 keysym du char é
  my $needle=chr(233);
  $chaine =~ s/é/${needle}/g;

  #232 keysym du char è
  $needle=chr(232);
  $chaine =~ s/è/${needle}/g;

  #231 keysym du char ç
  $needle=chr(231);
  $chaine =~ s/ç/${needle}/g;

  #224 keysym du char à
  $needle=chr(224);
  $chaine =~ s/à/${needle}/g;

  #176 keysym du char ° 
  $needle=chr(176);
  $chaine =~ s/°/${needle}/g;

  #163 keysym du char £
  $needle=chr(163);
  $chaine =~ s/£/${needle}/g;
   
  #249 keysym du char ù
  $needle=chr(249);
  $chaine =~ s/ù/${needle}/g;

  #181 keysym char µ
  $needle=chr(181);
  $chaine =~ s/µ/${needle}/g;

  #167 keysym du char §
  $needle=chr(167);
  $chaine =~ s/§/${needle}/g;

  #128 keysym du char €
  $needle=chr(128);
  $chaine =~ s/€/${needle}/g;
  
  return $chaine;

}

1;

