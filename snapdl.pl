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
use Getopt::Std;
use Digest::SHA;

my %opts;
getopts('vhipnrRc:s:a:S:P:C:t:V:', \%opts);

if ($opts{'h'} or $opts{'v'}) {
	print "snapdl 1.3.0-alpha (c) Nicolas P. M. Legrand 2010
usage: snapdl [-ihnprRv]  [-a arch] [-c countries] [-C command] [-P protocol]
       [-s sets_dest] [-S sets] [-t timeout] [-V version]
";
	exit 1;
}

#set conf dir
my $snapdl_dir = "$ENV{'HOME'}/.snapdl";
if (! -d $snapdl_dir) {
	printf "Creating $ENV{'HOME'}/.snapdl\n";
	mkdir "$ENV{'HOME'}/.snapdl" or die "can't mkdir $ENV{'HOME'}/.snapdl";
}

#set default conf
my %conf = ( 'version'   => 'snapshots',
	     'command'   => 'ftp',
	     'sets_dest' => "$ENV{'HOME'}/OpenBSD",
	     'sets'      => '^INSTALL|^bsd|tgz$',
	     'timeout'   => 1,
	     'protocol'  => 'http',
	     'arch'      => `uname -m`,
	     'countries' => ""
	    );

chomp($conf{'arch'});

#read deprecated ~/.snapdl/countries
if (-e "$snapdl_dir/countries") {
	open my $fh_countries, '<', "$ENV{'HOME'}/.snapdl/countries" or die "can't open $ENV{'HOME'}/.snapdl/countries";
	while (my $country = <$fh_countries>) {
		chomp($country);
		$conf{'countries'} .= ($conf{'countries'}) ? ",$country" : $country;
	}
	close $fh_countries;
	print "\n$snapdl_dir/countries is deprecated, you should run:
rm $snapdl_dir/countries
echo countries=$conf{'countries'} >> $snapdl_dir/.snapdl.conf\n\n";
}

#read ~/.snapdl/snapdl.conf and override defaults conf
if (-e "$ENV{'HOME'}/.snapdl/snapdl.conf") {
	open my $conf_file, '<', "$ENV{'HOME'}/.snapdl/snapdl.conf";
	while (<$conf_file>) {
		chomp;
		my @conf_entries = keys %conf;
		if(m!^([a-z_]+)=([A-Za-z,/~0-9\^\|\$\\]+)$!) {
			my $entry = $1;
			my $value = $2;
			if (grep /$entry/,@conf_entries) {
				$conf{$entry} = $value;
			} else {
				die "$_ is not a valid entry in $ENV{'HOME'}/.snapdl/snapdl.conf
could be any of: @conf_entries";
			}
		} else {
			die "Bad $ENV{'HOME'}/.snapdl/snapdl.conf format:\n $_\n";
		}
	}
}

#set booleans flags
$conf{'interactive'}     = $opts{'i'};
$conf{'pretend'}         = $opts{'p'};
$conf{'new_mirrors_dat'} = $opts{'n'};
$conf{'report'}          = $opts{'r'};
$conf{'report_packages'} = $opts{'R'};

#override default conf and snapdl.conf with command line options
$conf{'countries'} = $opts{'c'} if $opts{'c'};
$conf{'version'}   = $opts{'V'} if $opts{'V'};
$conf{'command'}   = $opts{'C'} if $opts{'C'};
$conf{'sets_dest'} = $opts{'s'} if $opts{'s'};
$conf{'sets'}      = $opts{'S'} if $opts{'S'};
$conf{'timeout'}   = $opts{'t'} if $opts{'t'};
$conf{'protocol'}  = $opts{'P'} if $opts{'P'};
$conf{'arch'}      = $opts{'a'} if $opts{'a'};

$conf{'sets_dest'} =~ s!^~!$ENV{'HOME'}!;

#check some conf values
die "You should set at least a country on the command line eg: -c France
or on ~/.snapdl/snapdl.conf: countries=France. You can had multiple countries
separated by commas, eg: France,Germany." unless $conf{'countries'}
|| $conf{'interactive'};
$, = ' ';
my @archs = ( "alpha", "amd64", "armish", "hp300", "hppa", "i386", "landisk",
	      "loongson", "macppc", "mvme68k", "mvme88k", "sgi", "socppc",
	      "sparc", "sparc64", "vax", "zaurus" );

my @versions = ("snapshots", "4.8", "4.7", "4.6");

die "$conf{'arch'} is an illegal arch value, possible values: @archs\n"
unless grep /$conf{'arch'}/, @archs;

die "$conf{'version'} is an illegal version value, possible values: @versions\n"
unless grep /$conf{'version'}/, @versions;

#special package report handling
if ($conf{'report_packages'}) {
	$conf{'pretend'} = 1;
	$conf{'report'}  = 1;
	$conf{'version'} .= "/packages";
	$conf{'timeout'} = 10 if $conf{'timeout'} == 1;
}

if (-e "$snapdl_dir/mirrors.dat" && $conf{'interactive'}) {
	my $mtime = (stat("$snapdl_dir/mirrors.dat"))[9];
	my $mod_date = localtime $mtime;
	print "You got your mirror list since $mod_date\n";
	print "Do you want a new one? [no] ";
	
	$conf{'new_mirrors_dat'} = <STDIN> =~ /^y/i;
} 
if (! -e "$snapdl_dir/mirrors.dat" || $conf{'new_mirrors_dat'}) {
	chdir($snapdl_dir);
	die "Can't get mirrors.dat\n"
	    if (system($conf{'command'}, "-omirrors.dat","http://www.OpenBSD.org/build/mirrors.dat") != 0);
}

#build the mirror list from mirrors.dat
open my $mirrors_dat, '<', "$ENV{'HOME'}/.snapdl/mirrors.dat"
    or die "Can't open $ENV{'HOME'}/.snapdl/mirrors.dat: $!";

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
	    && $1 !~ m!ftp.OpenBSD.org/pub/OpenBSD/!) {
		push @{ $mirrors{$current_country}->[1] }, $1;
	}
}

close $mirrors_dat;

#check mirrors from chosen countries
my @valid_countries = sort keys %mirrors;
for my $country (split ',', $conf{'countries'}) {
	die "$country is not a legal country value, valid entries are:
@valid_countries\n" unless exists $mirrors{$country}  || $conf{'interactive'};
	if (defined($mirrors{$country})) {
		$mirrors{$country}->[0] = "checked";
	}
}

&choose_country() if $conf{'interactive'};

#choose server protocol and build @mirrors, the list of candidate mirrors
if ($conf{'interactive'}) {
	printf "Protocols? ('ftp', 'http' or 'both') [http] ";
	chomp($conf{'protocol'} = <STDIN>);
}

my $proto_pattern;

if ($conf{'protocol'} eq "http") {
	$proto_pattern = "^http";
} elsif ($conf{'protocol'} eq "ftp") {
	$proto_pattern = "^ftp";
} else {
	$proto_pattern = "^ftp|^http";
}

my @mirrors ;
for (keys %mirrors) {
	if ($mirrors{$_}->[0] eq "checked") {
		for (@{ $mirrors{$_}->[1] }) {
			if (/$proto_pattern/) {
				push @mirrors, $_;
			}
		}
	}
}

#where to download sets
&choose_sets_dest() if $conf{'interactive'};

if (! -d $conf{'sets_dest'}) {
	system("mkdir", "-p", $conf{'sets_dest'});
	die "Can't mkdir -p $conf{'sets_dest'}" if $? != 0;
}
chdir($conf{'sets_dest'}) or die "Can't change dir to $conf{'sets_dest'}";

&choose_hw() if $conf{'interactive'};

#Download and check SHA256
my($fh_new_sha256, $new_sha256) = tempfile;
print "Getting SHA256 from main mirror\n";
`$conf{'command'} -o$new_sha256 http://ftp.OpenBSD.org/pub/OpenBSD/$conf{'version'}/$conf{'arch'}/SHA256`;

my @SHA256;

my $line_count = 0;
while (<$fh_new_sha256>) {
	$line_count += 1;
	if (! m!^SHA256 \([a-zA-Z0-9.\-_+@]+\) = [0-9a-zA-Z=+/]+.!s) {
		die "$_: bad SHA256 format from http://ftp.OpenBSD.org/. Aborting.\n";
	}
	push @SHA256, $_ if ! $conf{'report_packages'};
}
close($fh_new_sha256);

die "Empty or no SHA256 from http://ftp.OpenBSD.org/. Aborting.\n"
  if $line_count == 0;


if (compare($new_sha256, "SHA256.orig") == 0
    && ! $conf{'pretend'}) {
	die "You already have the last sets\n";
}

copy($new_sha256, "SHA256.orig") if (! $conf{'pretend'});

#Compare SHA256 with the one on each mirrors and put them in apropriate
#%<status>_mirror hash table
my %synced_mirror; # { 'http://mirror.com' => $time }
my %unsynced_mirror;
my %timeouted_mirror;
print "Let's locate mirrors synchronised with ftp.OpenBSD.org... ";
for my $candidat_server (@mirrors) {
        my $url = "${candidat_server}$conf{'version'}/$conf{'arch'}/SHA256";
        my ($fh_mirrored_sha256, $mirrored_sha256) = tempfile();
        my $time_before_dl = [gettimeofday];
        eval {
                local $SIG{ALRM} = sub {die "timeout\n"};
                alarm $conf{'timeout'};
                `$conf{'command'} -o$mirrored_sha256 $url 2>/dev/null`;
                alarm 0;
        };
        if ($@) {
                die unless $@ eq "timeout\n";
		close $fh_mirrored_sha256;
		$timeouted_mirror{$candidat_server} = "$conf{'timeout'}";
                next;
        } else {
                my $time = tv_interval $time_before_dl;
                if (compare($new_sha256, $mirrored_sha256) == 0) {
                        $synced_mirror{$candidat_server} = $time;
                } else {
			$unsynced_mirror{$candidat_server} = $time;
		}
		close $fh_mirrored_sha256;
        }
}

print "Done\n";

my @sorted_mirrors = sort {$synced_mirror{$a} <=> $synced_mirror{$b}} keys %synced_mirror;
die "No synchronised mirror found, try later..." if $#sorted_mirrors == -1
  && (!$conf{'report'} || $conf{'interactive'});

my $server = $sorted_mirrors[0] || "No server available";

&choose_mirror() if $conf{'interactive'};

#choose sets to download
my %sets; # {$set => $status} ; $set = "bsd" ; $status = "checked"

for (@SHA256) {
        /\((.+)\)/; 
	my $set = $1;
        my $status = ($set =~ /$conf{'sets'}/) ? "checked" : "not checked";
        $sets{$set} = $status;
}

&choose_sets() if $conf{'interactive'};

print "OK let's get the sets from $server!\n" unless $conf{'pretend'};

my @stripped_SHA256; #SHA256 stripped from undownloaded sets

#Download everything, or show commands that would have been used
if ($conf{'pretend'} && ! $conf{'report_packages'}) {
        print "Pretending:\n";
}

for my $set (sort keys %sets) {
	my @sha256_line = grep /\($set\)/, @SHA256;
	if ($sets{$set} eq "checked") {
		if (! $conf{'pretend'}) {
			system($conf{'command'}, "-o$set", "$server/$conf{'version'}/$conf{'arch'}/$set");
			push @stripped_SHA256, $sha256_line[0];
		} else {
			print "$conf{'command'} -o$set $server/$conf{'version'}/$conf{'arch'}/$set\n";
		}
	}
}

#And finally checksum the downloaded packages
if (! $conf{'pretend'}) {
        open my $fh_SHA256, '>', 'SHA256' or die $!;
        print $fh_SHA256 @stripped_SHA256;
	close $fh_SHA256;
        print "Checksum:\n";
	for (@stripped_SHA256) {
		my $sha = Digest::SHA->new(256);
		next unless (/^SHA256 \((.+)\) = ([a-zA-Z0-9]+)$/);
		$sha->addfile($1);
		if ($2 eq $sha->hexdigest) {
			print "(SHA256) $1: OK\n";
		} else {
			print "(SHA256) $1: FAILED\n";
		}
	}
        `ls -l >index.txt`;
}

&print_report() if $conf{'report'};

sub print_report
{
	print "\n\n";
	if (! $conf{'report_packages'}) {
		print "Reporting synchronization of sets repositories:\n";
		print "===============================================\n\n";
	} else {
		print "Reporting synchronization of packages repositories:\n";
		print "===================================================\n\n";
	}
	print "Synced mirrors:\n";
	if ($#sorted_mirrors == -1) {
		print "None\n";
	} else {
		for (@sorted_mirrors) {
			printf "%12f s.    %s\n", $synced_mirror{$_}, $_;
		}
	}
	print "\n";
	print "Unsynced mirrors:\n";
	my @sorted_unsynced = sort
	  {$unsynced_mirror{$a} <=> $unsynced_mirror{$b}}
	    keys %unsynced_mirror;
	if ($#sorted_unsynced == -1) {
		print "None\n";
	} else {
		for (@sorted_unsynced) {
			printf "%12f s.    %s\n", $unsynced_mirror{$_}, $_;
		}
	}
	print "\n";
	print "Timeouted mirrors:\n";
	my @timeouted_mirrors = sort {$timeouted_mirror{$a} <=> $timeouted_mirror{$b}}
	  keys %timeouted_mirror;
	if ($#timeouted_mirrors == -1) {
		print "None\n";
	} else {
		for (@timeouted_mirrors) {
			printf "%12f s.    %s\n", $timeouted_mirror{$_}, $_;
		}
	}
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
	CHOOSE: while (1) {
		print "Which countries you want to download from?:\n";
		my @countries;
		for (sort keys %mirrors) {
			my $box = ($mirrors{$_}->[0] eq "checked") ? "[x]" : "[ ]";
			push @countries, "$box $_";
		}
		format_check(\@countries);
		printf "Countries names? (or '?' or 'done') [done] ";
		chomp(my $line = <STDIN>);
		my $operation;
		my $pattern;
		if ($line eq "done" || $line eq "") {
			for (keys %mirrors) {
				if ($mirrors{$_}->[0] eq "checked") {
					last CHOOSE;
				}
			}
			print "\nYou should choose at least one country\n\n";
			next;
		} else {
			if ($line =~ /^(\+|-)?([a-zA-Z ]+)$/
			    && $line ne "?") {
				$operation = $1 || "+";
				$pattern = $2;
			} else {
				print "\n+re add countries with pattern re\n-re remove countries with pattern re\n\n";
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
		printf "Path to download sets? (or 'pretend' ) [$conf{'sets_dest'}] ";
		chomp(my $line = <STDIN>);
		if ($line eq "pretend") {
			$conf{'pretend'} = 1;
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
	while (1) {
		printf "Arch? (or 'list') [$conf{'arch'}] ";
		chomp(my $line = <STDIN>);
		if ($line eq 'list') {
			print "Available archs:\n";
			for (@archs) {
				print "    $_\n";
			}
			next;
		} elsif ($line) {
			if ((grep {/^$line$/} @archs) == 1) {
				$conf{'arch'} = $line;
				last;
			} else {
				printf "Bad arch name\n";
				next;
			}
		} else {
			if ((grep {/^$conf{'arch'}$/} @archs) == 1) {
				last;
			}
		}
	}
}

sub choose_mirror
{
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
		my @sets;
		print "Sets available:\n";
		for (sort keys %sets) {
			my $box = ($sets{$_} eq "checked") ? "[x]" : "[ ]";
			push @sets, "$box $_";
		}
		format_check(\@sets);
		printf "Set names? (or '?' or 'done') [done] ";
		chomp(my $line = <STDIN>);
		my $operation;
		my $pattern;
		if ($line eq "done" or $line eq "") {
			last;
		} else {
			if ($line =~ /^(\+|-)?(.+)$/
			    && $line ne "?") {
				$operation = $1 || "+";
				$pattern = $2;
			} else {
				print "\n+re add sets with pattern re\n-re remove sets with pattern re\n\n";
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
