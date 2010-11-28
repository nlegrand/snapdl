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
ok(sha256_file($sha_sets), 'sha256_file($file_name): return an hex SHA from file');
ok(cmp_files($sha_sets, $sha_sets_candidate),
   , 'cmp_files($f1, $f2): compare two sha256 from two files');

