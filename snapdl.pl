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


my $snapdl_dir = "$ENV{'HOME'}/.snapdl";
if (! -d $snapdl_dir) {
	printf "Creating $ENV{'HOME'}/.snapdl\n";
	mkdir "$ENV{'HOME'}/.snapdl" or die "can't mkdir $ENV{'HOME'}/.snapdl";
}
my $i_want_a_new_mirrors_dat;
if (-e "$snapdl_dir/mirrors.dat") {
	my $mtime = (stat("$snapdl_dir/mirrors.dat"))[9];
	my $mod_date = localtime $mtime;
	print "You got your mirror list since $mod_date\n";
	print "Do you want a new one? [no] ";
	chomp($i_want_a_new_mirrors_dat = <STDIN>);
} 
if (! -e "$snapdl_dir/mirrors.dat" || $i_want_a_new_mirrors_dat =~ /y|yes/i) {
	chdir($snapdl_dir);
	system("ftp", "http://www.openbsd.org/build/mirrors.dat");
}

open my $mirrors_dat, '<', "$ENV{'HOME'}/.snapdl/mirrors.dat" or die "can't open $ENV{'HOME'}/.snapdl/mirrors.dat";

my %mirrors;
my $current_country;
# autovivify %mirror :
# $mirror{'Country'} = ["not checked", [qw(ftp://blala.com http://blili.org)]]
while (<$mirrors_dat>) {
	chomp;
	if (/^GC\s+([a-zA-Z ]+)/) {
		$current_country = $1;
		if (! defined($mirrors{$current_country}->[0])) {
			$mirrors{$current_country}->[0] = "not checked";
		}
		
	} elsif (/(?:^UF|^UH)\s+([a-zA-Z0-9\.:\/-]+)/
	    && ! ($1 =~ m!ftp.OpenBSD.org/pub/OpenBSD/!)) {
		push @{ $mirrors{$current_country}->[1] }, $1;
	}
}

close $mirrors_dat;

my $fh_countries;
if (-e "$snapdl_dir/countries") {
	open $fh_countries, '<', "$ENV{'HOME'}/.snapdl/countries" or die "can't open $ENV{'HOME'}/.snapdl/countries";
	while (my $country = <$fh_countries>) {
		chomp($country);
		if (defined($mirrors{$country})) {
			$mirrors{$country}->[0] = "checked";
		}
	}
	close $fh_countries;
}

COUNTRY: {
        print "Which countries you want to download from?:\n";
	my @countries;
        for (sort keys %mirrors) {
		my $box = ($mirrors{$_}->[0] eq "checked") ? "[x]" : "[ ]";
		push @countries, "$box $_";
        }
	format_check(\@countries);
        printf "Countries name? (or 'done') [done] ";
        chomp(my $line = <STDIN>);
        my $operation;
        my $pattern;
        if ($line eq "done" || $line eq "") {
                print "Write the chosen countries in ~/.snapdl/countries to check them by default? [no] ";
	        chomp($line = <STDIN>);
	        if ($line =~ /y|yes/i) {
		        open $fh_countries, '>', "$ENV{'HOME'}/.snapdl/countries"
                            or die "can't open $ENV{'HOME'}/.snapdl/countries";
		        for (keys %mirrors) {
			        if ($mirrors{$_}->[0] eq "checked") {
                                        printf $fh_countries "$_\n";
                                }
		        }
                close $fh_countries;
	        }
                last COUNTRY;
        } else {
                if ($line =~ /(\+|-)(.+)/) {
                        $operation = $1;
                        $pattern = $2;
                } else {
                        print "+re add countries with pattern re\n-re remove countries with pattern re\n";
                        redo COUNTRY;
                        
                }
                for my $country (sort keys %mirrors) {
                        if ($country =~ /$pattern/
                            && $operation eq '-') {
                                $mirrors{$country}->[0] = "not checked";
                        } elsif ($country =~ /$pattern/
                                 && $operation eq '+') {
                                $mirrors{$country}->[0] = "checked";
                        }
                }
                redo COUNTRY;
        }
}

my @mirrors;
PROTOCOL: {
        printf "Protocols? ('ftp', 'http' or 'both') [http] ";
        chomp(my $line = <STDIN>);
        my $proto_pattern;
        if ($line =~ /^$|http/) {
                $proto_pattern = "^http";
        } elsif ($line =~ /ftp/) {
                $proto_pattern = "^ftp";
        } else {
                $proto_pattern = "^ftp|^http";
        }
        for (keys %mirrors) {
                if ($mirrors{$_}->[0] eq "checked") {
                        for (@{ $mirrors{$_}->[1] }) {
                                if (/$proto_pattern/) {
                                        push @mirrors, $_;
                                } 
                        }
                }   
        }
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



my %synced_mirror; # { 'http://mirror.com' => $time }
print "Let's locate mirrors synced with ftp.OpenBSD.org... ";
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
	my @sets;
        for (sort keys %sets) {
		my $box = ($sets{$_} eq "checked") ? "[x]" : "[ ]";
		push @sets, "$box $_";
        }
	format_check(\@sets);
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

if ($pretend eq "yes") {
        print "Pretending:\n";
}

for my $set (sort keys %sets) {
        if ($sets{$set} eq "checked"
            && $SHA256 =~ /(SHA256 \($set\) = [a-f0-9]+\n)/s) {
                if ($pretend eq "no") {
                        system("ftp", "-r 1", "$server/pub/OpenBSD/snapshots/$hw/$set");
                        push @stripped_SHA256, $1;
                } else {
                        print "ftp -r 1 $server/pub/OpenBSD/snapshots/$hw/$set\n";
                }
        }
}

if ($pretend eq "no") {
        open my $fh_SHA256, '>', 'SHA256';
        print $fh_SHA256 @stripped_SHA256;
        print "Checksum:\n" . `cksum -a sha256 -c SHA256` ;
}

sub format_check { # format_check(\@list)

	my $list_ref = shift @_;
	my $col_size = ($#{$list_ref} % 4 == 0) ? $#{$list_ref} / 4 : $#{$list_ref} / 4 + 1 ;
	for (my $i = 0; $i <= $col_size; $i++) {
		printf "%-20s",$list_ref->[$i];
		printf "%-20s",$list_ref->[$i + $col_size ] 
		    if (defined($list_ref->[$i + $col_size ])); 
		printf "%-20s",$list_ref->[$i + $col_size * 2]
		    if (defined($list_ref->[$i + $col_size * 2]));
		printf "%-20s",$list_ref->[$i + $col_size * 3]
		    if (defined($list_ref->[$i + $col_size * 3]));
		print "\n";
	}
}
