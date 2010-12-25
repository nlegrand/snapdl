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
use File::Temp qw(tempfile);
use File::Compare;
use File::Copy;

if ($#ARGV > -1) {
        print "usage: snapdl\n";
	exit 1;
}

my $snapdl_dir = "$ENV{'HOME'}/.snapdl";
if (! -d $snapdl_dir) {
	printf "Creating $ENV{'HOME'}/.snapdl\n";
	mkdir "$ENV{'HOME'}/.snapdl" or die "can't mkdir $ENV{'HOME'}/.snapdl";
}

my $interactive = "no";

open my $conf_file, '<', "$ENV{'HOME'}/.snapdl/snapdl.conf";
my %conf;
while (<$conf_file>) {
	chomp;
	if(m/^([a-z_]+)=([A-Za-z,\/~0-9]+)$/) {
		$conf{$1} = $2;
	}
}

$conf{'sets_dest'} =~ s!^~!$ENV{'HOME'}!;

my $i_want_a_new_mirrors_dat = "no";
if (-e "$snapdl_dir/mirrors.dat" && $interactive eq "yes") {
	my $mtime = (stat("$snapdl_dir/mirrors.dat"))[9];
	my $mod_date = localtime $mtime;
	print "You got your mirror list since $mod_date\n";
	print "Do you want a new one? [no] ";
	chomp($i_want_a_new_mirrors_dat = <STDIN>);
} 
if (! -e "$snapdl_dir/mirrors.dat" || $i_want_a_new_mirrors_dat =~ /y|yes/i) {
	chdir($snapdl_dir);
	system("ftp", "http://www.OpenBSD.org/build/mirrors.dat");
}

open my $mirrors_dat, '<', "$ENV{'HOME'}/.snapdl/mirrors.dat" or die "can't open $ENV{'HOME'}/.snapdl/mirrors.dat";

my %mirrors;
my $current_country;
# autovivify %mirrors :
# $mirrors{'Country'} = ["not checked", [qw(ftp://blala.com http://blili.org)]]
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

for my $country (split ',', $conf{'countries'}) {
	if (defined($mirrors{$country})) {
		$mirrors{$country}->[0] = "checked";
	}
}

&choose_country() if ($interactive eq "yes");

my @mirrors ;

if ($interactive eq "yes") {
	printf "Protocols? ('ftp', 'http' or 'both') [http] ";
	chomp($conf{'protocol'} = <STDIN>);
}

my $proto_pattern;

if ($conf{'protocol'} =~ /^$|http/) {
	$proto_pattern = "^http";
} elsif ($conf{'protocol'} =~ /ftp/) {
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

my $pretend = "no";


&choose_sets_dest() if ($interactive eq "yes");

chdir($conf{'sets_dest'}) or die "Can't change dir to $conf{'sets_dest'}";

chomp (my $hw = `uname -m`);

&choose_hw() if ($interactive eq "yes");

my( $fh_new_sha256, $new_sha256) = tempfile;

print "Getting SHA256 from main mirror\n";
`ftp -o $new_sha256 http://ftp.OpenBSD.org/pub/OpenBSD/snapshots/$hw/SHA256`;

my @SHA256;

while (<$fh_new_sha256>) {
	if (/^SHA256 \(base([0-9]{2,2}).tgz\) = [0-9a-zA-Z]+$/) {
		my $r = $1;
	} elsif (! /^SHA256 \([a-zA-Z0-9.]+\) = [0-9a-zA-Z]+$/) {
		die "No good SHA256 from http://ftp.OpenBSD.org/. Aborting.\n";
	}
	push @SHA256, $_;
}

if (compare($new_sha256, "SHA256.orig") == 0) {
	die "You already have the last sets\n";
}

copy($new_sha256, "SHA256.orig") if ($pretend eq "no");

my %synced_mirror; # { 'http://mirror.com' => $time }
print "Let's locate mirrors synchronised with ftp.OpenBSD.org... ";
for my $candidat_server (@mirrors) {
        my $url = "${candidat_server}snapshots/$hw/SHA256";
        my $time_before_dl = [gettimeofday];
        my ($fh_mirrored_sha256, $mirrored_sha256) = tempfile();
        eval {
                local $SIG{ALRM} = sub {die "timeout\n"};
                alarm 1;
                `ftp -o $mirrored_sha256 $url 2>/dev/null`;
                alarm 0;
        };
        if ($@) {
                die unless $@ eq "timeout\n";
		close $fh_mirrored_sha256;
                next;
        } else {
                my $time = tv_interval $time_before_dl;
                if (compare($new_sha256, $mirrored_sha256) == 0) {
                        $synced_mirror{$candidat_server} = $time;
                }
		close $fh_mirrored_sha256;
        }
}

close($fh_new_sha256);

print "Done\n";

my @sorted_mirrors = sort {$synced_mirror{$a} <=> $synced_mirror{$b}} keys %synced_mirror;
die "No synchronised mirror found, try later..." if $#sorted_mirrors == -1;

my $server = $sorted_mirrors[0];


&choose_mirror() if ($interactive eq "yes");

my $checked_set_pattern = "^INSTALL|^bsd|tgz\$";
my %sets; # {$set => $status} ; $set = "bsd" ; $status = "checked"

for (@SHA256) {
        my $set = (/\((.*)\)/) ? $1 : die "Weird SHA256\n";
        my $status = ($set =~ $checked_set_pattern) ? "checked" : "not checked";
        $sets{$set} = $status;
}

my @sets;

&choose_sets() if ($interactive eq "yes");

print "OK let's get the sets from $server!\n";

my @stripped_SHA256; #SHA256 stripped from undownloaded sets

if ($pretend eq "yes") {
        print "Pretending:\n";
}

for my $set (sort keys %sets) {
	my @sha256_line = grep /\($set\)/, @SHA256;
        if ($sets{$set} eq "checked") {
                if ($pretend eq "no") {
                        system("ftp", "-r 1", "$server/snapshots/$hw/$set");
                        push @stripped_SHA256, $sha256_line[0];
                } else {
                        print "ftp -r 1 $server/snapshots/$hw/$set\n";
                }
        }
}

if ($pretend eq "no") {
        open my $fh_SHA256, '>', 'SHA256' or die $!;
        print $fh_SHA256 @stripped_SHA256;
        print "Checksum:\n";
        system("cksum", "-a sha256", "-c", "SHA256") ;
        die "Bad checksum" if ($? != 0);
        my $str_index_txt = `ls -l`;
        open my $index_txt, '>', 'index.txt' or die $!;
        print $str_index_txt;
        print $index_txt $str_index_txt;
}

sub format_check { # format_check(\@list)

	my $list_ref = shift @_;
 	my $col_size = int($#{$list_ref} / 4);
	for (my $i = 0; $i <= $col_size; $i++) {
		printf "%-20s",$list_ref->[$i];
		for (my $j = 1; $j <= 3; $j++) {
		    printf "%-20s",$list_ref->[$i + ($col_size + 1) * $j]
			if (defined($list_ref->[$i + ($col_size + 1) * $j]));
		}
	        print "\n";
	}
}


sub choose_country
{
	while (1) {
		print "Which countries you want to download from?:\n";
		my @countries;
		for (sort keys %mirrors) {
			my $box = ($mirrors{$_}->[0] eq "checked") ? "[x]" : "[ ]";
			push @countries, "$box $_";
		}
		format_check(\@countries);
		printf "Countries names? (or 'done') [done] ";
		chomp(my $line = <STDIN>);
		my $operation;
		my $pattern;
		if ($line eq "done" || $line eq "") {
			last;
		} else {
			if ($line =~ /(\+|-)(.+)/) {
				$operation = $1;
				$pattern = $2;
			} else {
				print "+re add countries with pattern re\n-re remove countries with pattern re\n";
				next;
			}
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
                next;
        }
}

sub choose_sets_dest
{
	while(1) {
		$conf{'sets_dest'} = "$ENV{'HOME'}/OpenBSD";
		printf "Path to download sets? (or 'pretend' ) [$conf{'sets_dest'}] ";
		chomp(my $line = <STDIN>);
		if ($line eq "pretend") {
			$pretend = "yes";
			last;
		} elsif ($line) {
			$conf{'sets_dest'} = $line;
		} 
		if (! -d $conf{'sets_dest'}) {
			system("mkdir", "-p", $conf{'sets_dest'});
			die "Can't mkdir -p $conf{'sets_dest'}" if ($? != 0);
		}
		(! -d $conf{'sets_dest'} ) ? next : last;
	}
}


sub choose_hw
{
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

	while (1) {
		chomp($hw = `uname -m`);
		printf "Platform? (or 'list') [$hw] ";
		chomp(my $line = <STDIN>);
		if ($line eq 'list') {
			print "Available platforms:\n";
			for (@platforms) {
				print "    $_\n";
			}
			next;
		} elsif ($line) {
			if ((grep {/^$line$/} @platforms) == 1) {
				$hw = $line;
				last;
			} else {
				printf "Bad hardware platform name\n";
				next;
			}
		} else {
			if ((grep {/^$hw$/} @platforms) == 1) {
				last;
			}
		}
	}
}

sub choose_mirror {
	while (1) {
		print "Mirror? (or 'list') [$sorted_mirrors[0]] ";
		chomp(my $line = <STDIN>);
		if ($line eq "list") {
			print "Synchronised mirrors from fastest to slowest:\n";
			for (@sorted_mirrors) {
				print "    $_\n";
			}
			next;
		} elsif ($line eq "") {
			$server = $sorted_mirrors[0];
			last;
		} elsif ((grep {/^$line$/} @sorted_mirrors) == 1) {
			$server = $line;
			last;
		} else {
			print "Bad mirror string '$line'\n";
			next;
		}
	}
}

sub choose_sets
{
	while (1) {
		@sets = ();
		print "Sets available:\n";
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
			last;
		} else {
			if ($line =~ /(\+|-)(.+)/) {
				$operation = $1;
				$pattern = $2;
			} else {
				print "+re add sets with pattern re\n-re remove sets with pattern re\n";
				next;
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
			next;
		}
        }
}
