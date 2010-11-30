#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw(tempfile);
use Test::More "no_plan";

require 'Snapdl.pm';

my $dl = dl("ftp");

my ($fh_sha_sets_main, $sha_sets) = tempfile();
my ($fh_sha_sets_candidate, $sha_sets_candidate) = tempfile();

ok($dl->($sha_sets, "-V",
	 , 'http://ftp.OpenBSD.org/pub/OpenBSD/snapshots/i386/SHA256') == 0
   , 'dl($file_name, $uri) 1: Download SHA256 sets from main repository');
ok($dl->($sha_sets_candidate, "-V",
	 , 'http://ftp.fr.OpenBSD.org/pub/OpenBSD/snapshots/i386/SHA256') == 0
   , 'dl($file_name, $uri) 2: Download SHA256 sets from mirror');

