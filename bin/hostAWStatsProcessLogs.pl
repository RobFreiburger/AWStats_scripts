#!/usr/bin/perl
# Runs AWStats processing for hosts

use strict;
use XML::Simple qw(:strict);
use English '-no_match_vars';
use Benchmark; # Benchmarking

# Changeable variables
my $configurationXMLFile = "/srv/stats/etc/configuration.xml";
# Change everything else in XML file

# ENV untainting
$ENV{PATH} = '/usr/bin'; # Minimal PATH.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Read in XML configurations
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent = $xmlObject->XMLin($configurationXMLFile);

# Error logging subroutine
# Call using writeError("insert error message here");
sub writeError {
	my $errorString = join('', shift, "\n");
	my $dateTime = localtime;
	my $logEntry = join(' | ', $dateTime, $0, $errorString);
	
	# debugging
	print $logEntry;
	# open(ERRORLOG, ">>$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{errorLog}"); # Append mode
	# print ERRORLOG "$logEntry";
	# close(ERRORLOG);
}

sub runStats {
	my $host = $_[0];
	
	my $statsParameters = "-update -configdir=$configurationXMLContent->{localStorageDirectory}/etc/hostsConf -config=$host.$server";
	
	# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
	die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
	if ($pid) {
		while (<KID>) {
			"$configurationXMLContent->{AWStatsScriptLocation} ".
			$statsParameters;
		}
		close KID;
	} else {
		my @temp = ($EUID, $EGID);
		my $orig_uid = $UID;
		my $orig_gid = $GID;
		$EUID = $UID;
		$EGID = $GID;
		# Drop Privileges
		$UID = $orig_uid;
		$GID = $orig_gid;
		# Make sure privs are really gone
		($EUID, $EGID) = @temp;
		die "Can't drop privileges" unless $UID == $EUID and $GID eq $EGID;
		exec "$configurationXMLContent->{AWStatsScriptLocation}", $statsParameters or writeError("Cannot execute command '$configurationXMLContent->{AWStatsScriptLocation} $statsParameters: $!");
	}
}

# Run AWStats for each virtual host
foreach my $hostReference (@{$configurationXMLContent->{host}})
{
	next if $hostReference->{currentlyHosted} =~ m/^False$/i;
	
	my $hostName = $hostReference->{name};
	
	print "Processing $hostName\n"; # debugging
	
	mkdir("$configurationXMLContent->{localStorageDirectory}/host/$hostName") if !(-e "$configurationXMLContent->{localStorageDirectory}/host/$hostName");
	
	foreach my $serverReference (@{$hostReference->{server}}) {
		my $t0 = new Benchmark; # Benchmarking
		runStats($hostName, $serverReference->{name});
		my $t1 = new Benchmark; # Benchmarking
		my $td = timediff($t1, $t0); # Benchmarking
		print "$serverReference->{name} took:",timestr($td),"\n"; # Benchmarking
	}
}