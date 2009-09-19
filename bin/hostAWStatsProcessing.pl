#!/usr/bin/perl
# Writes configuration file per virtual host per server
# Then processes configuration through AWStats

use strict;
use XML::Simple qw(:strict);
use English '-no_match_vars';

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
	
	open(ERRORLOG, ">>$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{errorLog}"); # Append mode
	print ERRORLOG "$logEntry";
	close(ERRORLOG);
}

# Stats processing subroutine
# Call using runStats($hostName);
sub runStats {
	my $host = $_[0];
	
	# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
	die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
	if ($pid) {
		while (<KID>) {
			"$configurationXMLContent->{AWStatsScriptLocation} ".
			"-update -configdir=$configurationXMLContent->{localStorageDirectory}/etc/hostsConf -config=$host";
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
		exec "$configurationXMLContent->{AWStatsScriptLocation}", "-update", "-configdir=$configurationXMLContent->{localStorageDirectory}/etc/hostsConf", "-config=$host" 
		or writeError("Cannot execute command '$configurationXMLContent->{AWStatsScriptLocation} -update -configdir=$configurationXMLContent->{localStorageDirectory}/etc/hostsConf -config=$host: $!");
	}
}

# Make stats for every virtual host
foreach my $virtualHostReference (@{$configurationXMLContent->{host}})
{
	# Skip host if no longer hosted
	next if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
		
	# Variable definition
	my $hostName = $virtualHostReference->{name};
	my $hostAlias = $virtualHostReference->{hostAlias};
	my $localStatsLocation = $virtualHostReference->{localStatsLocation};
	my $statsConfigurationContents = ''; # each line of configuration file is indicated by this variable
	
	mkdir($localStatsLocation) if !(-e $localStatsLocation); # Make stats location dir
		
	# Configuration file header
	$statsConfigurationContents .= "# Configuration file for $hostName written by $0\n";
	$statsConfigurationContents .= '# Automatically generated: ' . scalar(localtime) . "\n";
	$statsConfigurationContents .= "\n";
	
	# Include template configuration file (location edited in XML file)
	$statsConfigurationContents .= "Include \"$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{templateConf}\"\n";
	$statsConfigurationContents .= "\n";
	$statsConfigurationContents .= "SiteDomain=\"$hostName\"\n"; # SiteDomain rewrite
	$statsConfigurationContents .= "HostAlias=\"$hostAlias\"\n"; # HostAlias rewrite
	$statsConfigurationContents .= "DirData=\"$localStatsLocation\"\n"; # DirData rewrite
	$statsConfigurationContents .= "\n";
	
	# Write conf for each server (much easier to debug)
	foreach my $serverReference (@{$virtualHostReference->{server}})
	{
		next if ($serverReference->{currentlyHosted} =~ m/^False$/i or $serverReference->{serverDisabled} =~ m/^True$/i);
				
		my $serverConfig = $statsConfigurationContents;
		
		# Comment about server name
		$serverConfig .= "# Server-specific information\n";
		$serverConfig .= "# Server: $serverReference->{name}\n";
		$serverConfig .= "\n";
		
		# LogFile writing
		# Define log file location
		my $logFile = "$serverReference->{localLogLocation}/$serverReference->{logName}";
		my $useLogResolve = 0; # 0 = don't (single log file), 1 = do (multiple log files)

		# Check to see if log file exists, is empty, and/or contains timestamp
		if (!(-e $logFile)) {
			writeError("$logFile - does not exist. Skipped.");
			next;
		} elsif (-z $logFile) {
			writeError("$logFile - is empty. Please check.");
			$useLogResolve = 1;
		} else {
			# Check for timestamp
			if ($serverReference->{logLastEntryTimestamp} !~ m/^False$/i)
			{
				# Timestamp recorded from last stats run

				# Slurp file contents
				my $logFileContents;
				{ local $/ = undef; local *FILE; open FILE, "<$logFile"; $logFileContents = <FILE>; close FILE }

				# If timestamp not found, set $useLogResolve
				$useLogResolve = 1 if $logFileContents !~ m/$serverReference->{logLastEntryTimestamp}/;
			}
			else
			{
				# Timestamp not recorded/found from last stats run
				$useLogResolve = 1;
			}
		}
		
		# Concat proper setting to $serverConfig
		if ($useLogResolve) {
			# Process multiple log files
			$serverConfig .= "LogFile=\"$configurationXMLContent->{AWStatsExamplesLocation}/logresolvemerge.pl $logFile\* |\"\n";
		} else {
			# Process one log
			$serverConfig .= "LogFile=\"$logFile\"\n";
		}
		
		# LogFormat rewrite
		# Note: it looks like three concats in a row, but only one concat actually happens
		$serverConfig .= "LogFormat=2\n" if $serverReference->{logFormat} =~ m/^IIS$/i; # Windows IIS
		$serverConfig .= "LogFormat=1\n" if $serverReference->{logFormat} =~ m/^combined$/i; # Apache standard "combined" format
		$serverConfig .= "LogFormat=4\n" if $serverConfig !~ m/LogFormat\=/; # all other kinds

		# Write configuration file
		my $confFile = "$configurationXMLContent->{localStorageDirectory}/etc/hostsConf/awstats.$hostName.conf";
		eval {
			open(HOSTCONF, ">$confFile") or die;
			print HOSTCONF $serverConfig;
			close(HOSTCONF) or die;
		};
		if ($@) {
			# Whoops
			writeError("$confFile - cannot write: $@. Skipped.");
			next;
		}
		
		# Run stats
		runStats($hostName);		
	}
}