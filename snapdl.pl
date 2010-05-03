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
use Time::HiRes qw(gettimeofday tv_interval);

if ($#ARGV >= 0) {
        print "usage: snapdl";
}

my $sets_dir; #path where to download sets
my $pretend = "no";
SETS: {
        $sets_dir = "$ENV{'HOME'}/OpenBSD";
        printf "Path to download sets? (or 'pretend' ) [$sets_dir] ";
        chomp(my $line = <STDIN>);
        if ($line eq "pretend") {
                $pretend = "yes";
                last SETS;
        } elsif ($line) {
                $sets_dir = $line;
        } 
        if (! -d $sets_dir) {
                `mkdir -p $sets_dir`;
        }
        (! -d $sets_dir ) ? redo SETS : chdir($sets_dir);
}


my @platforms = ( "alpha",
                  "amd64",
                  "armish",
                  "hp300",
                  "hppa",
                  "i386",
                  "landisk",
                  "loongson",
                  "macppc",
                  "mvme68k",
                  "mvme88k",
                  "sgi",
                  "socppc",
                  "sparc",
                  "sparc64",
                  "vax",
                  "zaurus" );
my $hw;
HW: {
        chomp($hw = `uname -m`);
        printf "Platform? (or 'list') [$hw] ";
        chomp(my $line = <STDIN>);
        if ($line eq 'list') {
                print "Avaible Platforms:\n";
                for (@platforms) {
                        print "    $_\n";
                }
                redo HW;
        } elsif ($line) {
                if ((grep {/$line/} @platforms) == 1) {
                        $hw = $line;
                        last HW;
                } else {
                        printf "bad hardware platform name\n";
                        redo HW;
                }
        }
}

print "Getting SHA256 from main mirror\n";
my $SHA256 = `ftp -o - http://ftp.OpenBSD.org/pub/OpenBSD/snapshots/$hw/SHA256`;

if ( $SHA256 =~ /base([0-9]{2,2}).tgz/ ) {
        my $r = $1;
} else {
        die "No good SHA256 from http://ftp.OpenBSD.org. Aborting.\n";
}

print "Getting ftp list from official Web site\n";
my @ftp_html = split /\n/, `ftp -o - http://www.openbsd.org/ftp.html`; 
my @mirrors;
for (@ftp_html) {
        if (/^\s+(http:\/\/.+)</ && (! /ftp\.OpenBSD\.org/)) {
                push @mirrors, $1;
        }
}

my %synced_mirror; # { 'http://mirror.com' => $time }
print "Let's locate mirrors synced with ftp.OpenBSD.org (this may take some time)... ";
for my $candidat_server (@mirrors) {
        my $url = "${candidat_server}snapshots/$hw/SHA256";
        $candidat_server =~ s!/pub/OpenBSD/!!;
        my $time_before_dl = [gettimeofday];
        my $mirrored_SHA256;
        eval {
                local $SIG{ALRM} = sub {die "timeout\n"};
                alarm 1;
                $mirrored_SHA256 = `ftp -o - $url 2>/dev/null`;
                alarm 0;
        };
        if ($@) {
                die unless $@ eq "timeout\n";
                next;
        } else {
                my $time = tv_interval $time_before_dl;
                if ($SHA256 eq $mirrored_SHA256) {
                        $synced_mirror{$candidat_server} = $time;
                }
        }
}
print "Done\n";

my $server;
my @sorted_mirrors = sort {$synced_mirror{$a} <=> $synced_mirror{$b}} keys %synced_mirror;
die "No mirror found" if $#sorted_mirrors == -1;

MIRROR: {
        print "Mirror? (or 'list') [$sorted_mirrors[0]] ";
        chomp(my $line = <STDIN>);
        if ($line eq "list") {
                print "Synced mirrors from fastest to slowest:\n";
                for (@sorted_mirrors) {
                        print "    $_\n";
                }
                redo MIRROR;
        } elsif ($line eq "") {
                $server = $sorted_mirrors[0];
                last MIRROR;
        } elsif ((grep {/^$line$/} @sorted_mirrors) == 1) {
                $server = $line;
                last MIRROR;
        } else {
                print "Bad mirror string '$line'\n";
                redo MIRROR;
        }
}


my $checked_set_pattern = "^INSTALL|^bsd|tgz\$";
my %sets; # {$set => $status} ; $set = "bsd" ; $status = "checked"

for (split /\n/s, $SHA256) {
        my $set = (/\((.*)\)/) ? $1 : die "Weird SHA256\n";
        my $status = ($set =~ $checked_set_pattern) ? "checked" : "not checked";
        $sets{$set} = $status;
}

SETS: {
        print "Sets available:\n";
        for (sort keys %sets) {
            my $box = ($sets{$_} eq "checked") ? "[x]" : "[ ]";
                        print "$box $_\n";
        }
        printf "Set names? (or 'done') [done] ";
        chomp(my $line = <STDIN>);
        my $operation;
        my $pattern;
        if ($line eq "done" or $line eq "") {
                last SETS;
        } else {
                if ($line =~ /(\+|-)(.+)/) {
                        $operation = $1;
                        $pattern = $2;
                } else {
                        print "+re add sets with pattern re\n-re remove sets with pattern re\n";
                        redo SETS;
                        
                }
                for my $set (sort keys %sets) {
                        if ($set =~ /$pattern/
                            && $operation eq '-') {
                                $sets{$set} = "not checked";
                        } elsif ($set =~ /$pattern/
                                 && $operation eq '+') {
                                $sets{$set} = "checked";
                        }
                }
                redo SETS;
        }
}


print "OK let's get the sets from $server!\n";

my @stripped_SHA256; #SHA256 stripped from undownloaded sets

my @checked_sets;
for my $set (sort keys %sets) {
                if ($sets{$set} eq "checked"
                    && $SHA256 =~ /(SHA256 \($set\) = [a-f0-9]+\n)/s) {
                        if ($pretend eq "no") {
                                system("ftp", "-r 1", "$server/pub/OpenBSD/snapshots/$hw/$set");
                                push @stripped_SHA256, $1;
                        }
                }
}

if ($pretend eq "no") {
        open my $fh_SHA256, '>', 'SHA256';
        print $fh_SHA256 @stripped_SHA256;
        print "Checksum:\n" . `cksum -a sha256 -c SHA256` ;
}
