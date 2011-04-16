#!/usr/bin/perl

# Copyright (c) 2005 Victor Semionov <vsemionov@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



# $Id: pkg-orphan.pl,v 1.3 2006-03-03 03:19:12 semionov Exp $

#use warnings;
use strict;

use Getopt::Std;



my $version = "0.1.1";
my $dbdir = (exists $ENV{PKG_DBDIR}? $ENV{PKG_DBDIR} : "/var/db/pkg");
my $keeplist = $dbdir . "/orphans.lst";
my %opts;
getopts("aAbBdhklLnpqrv", \%opts);

&one_switch("aAdhklLv");
&one_switch("bB");

if ($opts{v})
{
	&version();
}
elsif ($opts{h})
{
	&usage();
}
elsif ($opts{k})
{
	&load_kept(@ARGV);
	&list_kept();
}
elsif ($opts{l} || $opts{L})
{
	&load_orphans(@ARGV);
	&list_orphans();
}
elsif ($opts{a} || $opts{A})
{
	&load_kept();
	&add_kept($opts{A}, $opts{A}? &load_orphans(@ARGV? @ARGV : undef) : @ARGV);
	&save_kept();
}
elsif ($opts{d})
{
	&load_kept();
	&del_kept(@ARGV);
	&save_kept();
}
else
{
	&load_orphans(@ARGV);
	&load_kept();
	&sel_ops();
	&save_kept();
	&do_ops();
}






sub version
{
	my $help = "pkg-orphan $version\nCopyright (c) 2005 Victor Semionov <vsemionov\@gmail.com>\n";
	print $help;
}

sub usage
{
	&version();

	my $help = "
Usage: pkg-orphan [-bBnpqr] [-a | -A | -d | -h | -k | -l | -L | -v] [name ...]

Without any switches, pkg-orphan enters interactive mode, asking what to do for
each unreferenced (orphan) package. Previously kept packages are skipped.

Commands:
  -a Add names to the keep-list.
  -A Same as -a, but limited to installed orphan package names.
  -d Delete names from the keep-list.
  -h Show this usage help.
  -k Show the keep-list.
  -l List orphan packages.
  -L Detailed list orphan packages.
  -v Show version.

Switches:
  -b Batch mode. Delete orphan packages, not present in the keep-list.
  -B Batch mode. Keep orphan packages and add them to the keep-list.
  -n Dry run. Don't delete or change anything, just show what would be done.
  -q Be quiet. Only print errors and decision prompts when interactive.
  -p Interpret <name> as a regular expression.
  -r Delete packages recursively. This will not delete shared dependencies.

";

	print $help;
}

sub get_packages
{
	my @list;
	my $pkg;
	chdir $dbdir or die "$0: Unable to change to directory $dbdir: $!\n";
	if (!opendir DBDIR, ".")
	{
		warn "$0: Unable to read directory $dbdir: $!\n";
		return ();
	}
	while ($pkg = readdir DBDIR)
	{
		if (($pkg ne ".") && ($pkg ne "..") && (-f "$pkg/+COMMENT"))
		{
			push @list, $pkg;
		}
	}
	close DBDIR;
	@list;
}

sub get_list
{
	my ($pkg, $file, $pat, $pre, $post) = @_;
	$file = "$dbdir/$pkg/$file";
	open FILE, $file or return undef;
	$pat = '.*' unless defined $pat;
	$pat = "$pre($pat)$post";
	my @list;
	while (<FILE>)
	{
		chomp;
		push @list, $1 if /$pat/;
	}
	close FILE;
	@list;
}

sub get_deps
{
	my $pkg = shift;
	&get_list($pkg, "+CONTENTS", '\S+', '^@pkgdep ');
}

sub get_reqs
{
	my $pkg = shift;
	&get_list($pkg, "+REQUIRED_BY", '\S+');
}

sub is_orphan
{
	my $pkg = shift;
	not int &get_reqs($pkg);
}

sub get_desc
{
	my $pkg = shift;
	(&get_list($pkg, "+COMMENT"))[0];
}

sub get_orphans
{
	my ($isre, @names) = @_;
	my @list;
	foreach my $pkg (&get_packages)
	{
		my $pn = &get_name($pkg);
		next if ( @names && !&grep_inverse($isre, $pn, \@names) );
		push @list, $pkg if &is_orphan($pkg);
	}
	@list;
}

sub ask_user
{
	my ($pkg, $num, $total) = @_;
	print "\n";
	print "Package $num of $total:\n";
	print "$pkg: ", &get_desc($pkg), "\n";
	print "$pkg: Delete/Keep/Ignore? [I]: ";
	my $ans = substr <STDIN>, 0, 1;
	print "\n";
	(int $ans =~ m/d/i, int $ans =~ m/k/i);
}

sub get_name
{
	my $pkg = shift;
	my ($name) = $pkg =~ /(.*)-.*/;
	$name;
}

sub in_names
{
	my ($pkg, $hash) = @_;
	exists $$hash{&get_name($pkg)};
}

sub grep_inverse
{
	my ($isre, $pat, $list) = @_;
	grep { $isre? $pat =~ /$_/ : $pat eq $_ } @$list;
}




my @orphans;
my %kept;
my %newkept;
my @ops;
my %deleted;


sub state
{
	print "===>  @_\n" unless $opts{q};
}

sub item
{
	my ($itm, $sgn) = @_;
	print "   [" . ($sgn? "+" : "-") . "] $itm\n" unless $opts{q};
}

sub load_orphans
{
	my @names = @_;
	&state("Loading list of orphaned packages.");
	@orphans = sort &get_orphans($opts{p}, @names);
}

sub list_orphans
{
	if ($opts{L})
	{
		&state("Listing orphaned packages (verbose).");
		print "$_: ", &get_desc($_), "\n" for (@orphans);
	}
	elsif ($opts{l})
	{
		&state("Listing orphaned packages.");
		print "$_\n" for (map &get_name($_), @orphans);
	}
	my $cnt = @orphans;
	&state("$cnt packages listed.");
}

sub load_kept
{
	my ($isre, @names) = ($opts{p}, @_);
	&state("Loading list of kept packages.");
	if (-f $keeplist)
	{
		open KEEP, $keeplist or warn "$0: Unable to read file $keeplist: $!\n";
		while (<KEEP>)
		{
			chomp;
			$kept{$_} = 1
				unless ( @names && !&grep_inverse($isre, $_, \@names) );
		}
		close KEEP;
	}
}

sub save_kept
{
	if (my @newnames = sort keys %newkept)
	{
		&add_kept(0, @newnames);
	}
	&state("Saving new list of kept packages.");
	unless ($opts{n})
	{
		if (open KEEP, ">$keeplist")
		{
			print KEEP "$_\n" foreach (sort keys %kept);
			close KEEP;
		}
		else
		{
			warn "$0: Unable to write file $keeplist: $!\n";
		}
	}
}

sub list_kept
{
	&state("Listing kept packages.");
	my @list = sort keys %kept;
	my $cnt = @list;
	print "$_\n" for (@list);
	&state("$cnt names listed.");
}

sub add_kept
{
	my $full = shift;
	my @names = @_;
	&state("Adding names to the list of kept packages.");
	my $cnt = 0;
	foreach my $pkg (@names)
	{
		my $name = (!$full? $pkg : &get_name($pkg));
		unless (exists $kept{$name})
		{
			&item($name, 1);
			$kept{$name} = 1;
			$cnt++;
		}
	}
	&state("$cnt names added.");
}

sub del_kept
{
	my ($isre, @names) = ($opts{p}, @_);
	&state("Removing names from the list of kept packages.");
	my $cnt = 0;
	foreach my $pkg (sort keys %kept)
	{
		if (&grep_inverse($isre, $pkg, \@names))
		{
			&item($pkg);
			delete $kept{$pkg};
			$cnt++;
		}
	}
	&state("$cnt names deleted.");
}

sub sel_ops
{
	&state("Selecting operations for packages.");
	my $unkept = @orphans - grep &in_names($_, \%kept), @orphans;
	for (my $i = my $idx = 0; $i<@orphans; $i++)
	{
		my $pkg = $orphans[$i];
		push @ops, 3;
		next if &in_names($pkg, \%kept);
		my ($del, $keep) = ($opts{b}, $opts{B});
		unless ($del || $keep)
		{
			($del, $keep) = &ask_user($pkg, ++$idx, $unkept);
		}
		$newkept{&get_name($pkg)} = 1 if $keep;
		$ops[-1] = ($del<<1) + $keep;
	}
}

sub do_ops
{
	&state("Performing selected operations on packages.");
	my @op_names = ("Ignoring", "Keeping ", "Deleting", "Skipping");
	my @cnt = (0, 0, 0, 0);
	foreach my $pkg (@orphans)
	{
		my $op = shift @ops;
		$cnt[$op]++;
		print "=> ", $op_names[$op], " $pkg\n" unless $opts{q};
		if ($op==2)
		{
			&pkg_delete($pkg, $opts{r}, $opts{n});
		}
	}
	my @dellist = values %deleted;
	my $ndel = grep { $_ != 0 } @dellist;
	my $nfail = @dellist - $ndel;
	my $norph = @orphans;
	&state("$norph considered: $ndel/$cnt[2] deleted, $cnt[1] kept, $cnt[3] skipped, $cnt[0] ignored; $nfail failed.");
}

sub wouldbe_orphan
{
	my $pkg = shift;
	not grep !exists $deleted{$_}, &get_reqs($pkg);
}

sub pkg_delete
{
	my ($pkg, $rec, $nop) = @_;
	my @list = $pkg;
	push @list, reverse &get_deps($pkg) if $rec;
	for (my $i=0; $i<@list; $i++)
	{
		my $cur = $list[$i];
		if (!$i || (!&in_names($cur, \%kept) && &wouldbe_orphan($cur)))
		{
			&item($cur);
			my $res = 0;
			$res = system "pkg_delete", $cur unless $nop;
			$deleted{$cur} = !$res;
		}
	}
}

sub one_switch
{
	my @arg = split(//, shift);
	my @con = grep { exists $opts{$_} } @arg;
	die "$0: Conflicting switches -$con[0] and -$con[1]\n"
		if (@con > 1);
}
