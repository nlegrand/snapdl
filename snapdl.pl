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

if ($#ARGV > -1) {
        print "usage: snapdl\n";
	exit 1;
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

sub country
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

&country();

my @mirrors;

sub protocol
{
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

&protocol();

my $sets_dir; #path where to download sets
my $pretend = "no";

#interactively set installation sets destination
sub sets_destination
{
	while(1) {
		$sets_dir = "$ENV{'HOME'}/OpenBSD";
		printf "Path to download sets? (or 'pretend' ) [$sets_dir] ";
		chomp(my $line = <STDIN>);
		if ($line eq "pretend") {
			$pretend = "yes";
			last;
		} elsif ($line) {
			$sets_dir = $line;
		} 
		if (! -d $sets_dir) {
			system("mkdir", "-p", $sets_dir);
			die "Can't mkdir -p $sets_dir" if ($? != 0);
		}
		(! -d $sets_dir ) ? next : chdir($sets_dir);
		last;
	}
}

&sets_destination();

chomp (my $hw = `uname -m`);

sub hw_platform
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

&hw_platform();

print "Getting SHA256 from main mirror\n";
my $SHA256 = `ftp -o - http://ftp.OpenBSD.org/pub/OpenBSD/snapshots/$hw/SHA256`;

if ( $SHA256 =~ /base([0-9]{2,2}).tgz/ ) {
        my $r = $1;
} else {
        die "No good SHA256 from http://ftp.OpenBSD.org/. Aborting.\n";
}



my %synced_mirror; # { 'http://mirror.com' => $time }
print "Let's locate mirrors synchronised with ftp.OpenBSD.org... ";
for my $candidat_server (@mirrors) {
        my $url = "${candidat_server}snapshots/$hw/SHA256";
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

my @sorted_mirrors = sort {$synced_mirror{$a} <=> $synced_mirror{$b}} keys %synced_mirror;
die "No synchronised mirror found, try later..." if $#sorted_mirrors == -1;

my $server = $sorted_mirrors[0];

#choose your mirror
sub mirror {
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

&mirror();

my $checked_set_pattern = "^INSTALL|^bsd|tgz\$";
my %sets; # {$set => $status} ; $set = "bsd" ; $status = "checked"

for (split /\n/s, $SHA256) {
        my $set = (/\((.*)\)/) ? $1 : die "Weird SHA256\n";
        my $status = ($set =~ $checked_set_pattern) ? "checked" : "not checked";
        $sets{$set} = $status;
}

my @sets;

sub sets_to_download
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

&sets_to_download();


print "OK let's get the sets from $server!\n";

my @stripped_SHA256; #SHA256 stripped from undownloaded sets

if ($pretend eq "yes") {
        print "Pretending:\n";
}

for my $set (sort keys %sets) {
        if ($sets{$set} eq "checked"
            && $SHA256 =~ /(SHA256 \($set\) = [a-f0-9]+\n)/s) {
                if ($pretend eq "no") {
                        system("ftp", "-r 1", "$server/snapshots/$hw/$set");
                        push @stripped_SHA256, $1;
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
