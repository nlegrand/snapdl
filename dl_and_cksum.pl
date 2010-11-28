#!/usr/bin/perl

# Copyright (c) 2010 Nicolas P. M. Legrand <nlegrand@ethelred.fr>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use Digest::SHA;

#hardwritten yet
my $tmp = "/tmp/snapdl";
my $dir = "$ENV{'HOME'}/OpenBSD";

my $command = "ftp"; #will be curl on Linux

my $SHA256_sets               = "$dir/SHA256.sets";
my $SHA256_packages           = "$dir/SHA256.packages";
my $SHA256_sets_candidate     = "$tmp/SHA256.sets";
my $SHA256_packages_candidate = "$tmp/SHA256.packages";
my $SHA256_sets_location      = "/pub/OpenBSD/snapshots/i386/SHA256";
my $SHA256_packages_location  = "/pub/OpenBSD/snapshots/packages/i386/SHA256";

my $main_mirror = "http://ftp.openbsd.org";
my $mirror      = "http://ftp.fr.openbsd.org";

system($command, "-o", $SHA256_sets, $main_mirror . $SHA256_sets_location);
system($command, "-o", $SHA256_packages, $main_mirror . $SHA256_packages_location);

system($command, "-o", $SHA256_sets_candidate, $mirror . $SHA256_sets_location);
system($command, "-o", $SHA256_packages_candidate, $mirror . $SHA256_packages_location);

my $sha_sets_main     = Digest::SHA->new(256);
$sha_sets_main->addfile($SHA256_sets);
my $sha_packages_main = Digest::SHA->new(256);
$sha_packages_main->addfile($SHA256_packages);

my $sha_sets_candidate     = Digest::SHA->new(256);
$sha_sets_candidate->addfile($SHA256_sets_candidate);
my $sha_packages_candidate = Digest::SHA->new(256);
$sha_packages_candidate->addfile($SHA256_packages_candidate);

($sha_sets_main->hexdigest eq $sha_sets_candidate->hexdigest) ?
    print "Sets candidate is synched\n" :
    print "Sets candidate is not synched\n";

($sha_packages_main->hexdigest eq $sha_packages_candidate->hexdigest) ?
    print "package candidate is synched\n" :
    print "package candidate is not synched\n";
