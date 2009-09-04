#!/usr/bin/perl

use strict;
use XML::Simple qw(:strict);
use English '-no_match_vars';

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in XML file

# ENV untainting
delete @ENV{qw(IFS CDPATH ENV BASH_ENV PATH)};

# Read in XML configuration
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent = $xmlObject->XMLin($configurationXMLFile);

# Error logging subroutine
# Call using writeError("insert error message here");
sub writeError {
	my $errorString = join('', shift, "\n");
	my $dateTime = localtime;
	my $logEntry = join(' | ', $dateTime, $0, $errorString);
	
	open(ERRORLOG, ">>$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{errorLog}"); # Append mode
	print ERRORLOG "$logEntry";
	close(ERRORLOG);
}

# Stats processing subroutine
# Call using writeError($serverName);
sub runStats {
	my $host = $_[0];
	
	# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
	die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
	if ($pid) {
		while (<KID>) {
			"$configurationXMLContent->{AWStatsScriptLocation} ".
			"-update -configdir=$configurationXMLContent->{localStorageDirectory}/etc/serverConf -config=$host";
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
		exec "$configurationXMLContent->{AWStatsScriptLocation}", "-update", "-configdir=$configurationXMLContent->{localStorageDirectory}/etc/serverConf", "-config=$host" 
		or writeError("Cannot execute command '$configurationXMLContent->{AWStatsScriptLocation} -update -configdir=$configurationXMLContent->{localStorageDirectory}/etc/serverConf -config=$host: $!");
	}
}

# Make stats for every server
foreach my $serverReference (@{$configurationXMLContent->{server}})
{
	# Skip server if disabled
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	
	# Variable declaration
	my $serverName = $serverReference->{name};
	my $statsConfigurationContents = '';
	my $storageLocation = "$configurationXMLContent->{localStorageDirectory}/etc/serverConf";
	
	mkdir($storageLocation) if !(-e $storageLocation);
	
	# Configuration header
	$statsConfigurationContents .= "# Configuration file for $serverName written by $0\n";
	$statsConfigurationContents .= '# Automatically generated: ' . scalar(localtime). "\n";
	$statsConfigurationContents .= "\n";
	
	# Include template configuration file (location edited in XML file)
	$statsConfigurationContents .= "Include \"$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{templateConf}\"\n";
	$statsConfigurationContents .= "\n";
	
	foreach my $virtualHostReference (@{$serverReference->{host}})
	{
		# Skip server if not hosted with Alliance
		next if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
		
		# Transfer for per-host configuration
		my $hostConfig = $statsConfigurationContents;
		
		# Per-host configuration
		$hostConfig .= "SiteDomain=\"$virtualHostReference->{name}\"\n"; # SiteDomain rewrite
		$hostConfig .= "HostAlias=\"$virtualHostReference->{hostAlias}\"\n"; # HostAlias rewrite
		$hostConfig .= "DirData=\"$configurationXMLContent->{localStorageDirectory}/server/$serverName/stats\"\n"; # DirData rewrite
		$hostConfig .= "LogFile=\"$configurationXMLContent->{AWStatsExamplesLocation}/logresolvemerge.pl $virtualHostReference->{localLogLocation}/$virtualHostReference->{logName}\* |\"\n"; # LogFile rewrite
		
		# LogFormat rewrite
		# Note: it looks like three concats in a row, but only one concat actually happens
		$hostConfig .= "LogFormat=2\n" if $virtualHostReference->{logFormat} =~ m/^IIS$/i; # Windows IIS
		$hostConfig .= "LogFormat=1\n" if $virtualHostReference->{logFormat} =~ m/^combined$/i; # Apache standard "combined" format
		$hostConfig .= "LogFormat=4\n" if $hostConfig !~ m/LogFormat\=/; # all other kinds
		
		# Write configuration file
		my $confFile = "$configurationXMLContent->{localStorageDirectory}/etc/serverConf/awstats.$serverName.conf";
		eval {
			open(SERVERCONF, ">$confFile") or die;
			print SERVERCONF $hostConfig;
			close(SERVERCONF) or die;
		};
		if ($@) {
			# Whoops
			writeError("$confFile - cannot write: $@. Skipped.");
			next;
		}
		
		# Run stats
		runStats($serverName);
	}
}