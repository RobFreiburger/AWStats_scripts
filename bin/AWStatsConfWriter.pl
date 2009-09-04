#!/usr/bin/perl -wT
# Rewrites configuration files per server per virtual host for AWStats

use strict;
use XML::Simple qw(:strict);

# Changeable variables
my $configurationXMLFile = "/srv/stats/etc/configuration.xml";
# Change everything else in XML file

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

# Rewrite AWStats configuration file for each host
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	
	my $serverName = $serverReference->{name};
	
	foreach my $virtualHostReference (@{$serverReference->{host}}) {
		next if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
		
		my $virtualHostName = $virtualHostReference->{name};
		my $hostLog = "$virtualHostReference->{localLogLocation}/$virtualHostReference->{logName}";
		my $hostConfContents;
		
		# Header for conf file
		$hostConfContents .= "# Configuration File for $virtualHostName generated by AWStatsConfWriter.pl\n";
		$hostConfContents .= "# Generated: " . scalar(localtime) . "\n\n";
		
		# Include template configuration file
		$hostConfContents .= "Include \"$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{templateConf}\"" . "\n";
		
		# LogFile rewrite
		# Varies based on finding log and last known timestamp
		if (!(-e $hostLog)) {
			# Log doesn't exist; write error and skip
			writeError("$hostLog - does not exist. $virtualHostName stats processing skipped.");
			next;
		} elsif (-z $hostLog) {
			# Log is empty for some reason; write error, default to parse all similar logs
			writeError("$hostLog - empty file. Please check.");
			$hostConfContents .= "LogFile=\"$configurationXMLContent->{AWStatsExamplesLocation}/logresolvemerge.pl $hostLog\* \|\"" . "\n";
		} else {
			if ($virtualHostReference->{logLastEntryTimestamp} !~ m/^false$/i) {
				# If timestamp found, use only the most recent log and save processing time
				my $logContents;
				{ local $/ = undef; local *FILE; open FILE, "<$hostLog"; $logContents = <FILE>; close FILE }
			
				if ($logContents =~ m/$virtualHostReference->{logLastEntryTimestamp}/) {
					$hostConfContents .= "LogFile=\"$hostLog\"" . "\n";
				} else {
					$hostConfContents .= "LogFile=\"$configurationXMLContent->{AWStatsExamplesLocation}/logresolvemerge.pl $hostLog\* \|\"" . "\n";
				}
			} else {
				$hostConfContents .= "LogFile=\"$configurationXMLContent->{AWStatsExamplesLocation}/logresolvemerge.pl $hostLog\* \|\"" . "\n";
			}
		}
		
		# SiteDomain rewrite
		$hostConfContents .= "SiteDomain=\"$virtualHostName\"\n";
		
		# HostAliases rewrite
		$hostConfContents .= "HostAliases=\"$virtualHostReference->{hostAlias}\"\n";
		
		# DirData rewrite
		$hostConfContents .= "DirData=\"$configurationXMLContent->{localStorageDirectory}/server/$serverName/$virtualHostName/stats\"\n";
		
		# LogFormat rewrite
		if ($virtualHostReference->{logFormat} =~ m/^combined$/i) {
			# Use LogFormat type 1
			$hostConfContents .= 'LogFormat=1';
		} elsif ($virtualHostReference->{logFormat} =~ m/^IIS$/i) {
			# Use LogFormat type 2
			$hostConfContents .= 'LogFormat=2';
		} else {
			# Use LogFormat type 4
			# NOTE: some features (browsers, os, keywords...) can't work.
			$hostConfContents .= 'LogFormat=4';
		}
		$hostConfContents .= "\n";
		
		my $AWStatsConf = "$configurationXMLContent->{localStorageDirectory}/server/$serverName/$virtualHostName/awstats.$virtualHostName.conf";
		eval {
			# Make directories and write conf file
			mkdir("$configurationXMLContent->{localStorageDirectory}/server/$serverName/$virtualHostName") if !(-e "$configurationXMLContent->{localStorageDirectory}/server/$serverName/$virtualHostName");
			open(HOSTCONF, ">$AWStatsConf") or die;
			print HOSTCONF "$hostConfContents";
			close(HOSTCONF) or die;
		};
		if ($@) {
			# Whoops
			writeError("$AWStatsConf - cannot write: $@");
		}
	}
}