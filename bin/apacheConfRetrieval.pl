#!/usr/bin/perl
# Retrieves and parses Apache virtual host confs

use strict;
use XML::Simple qw(:strict);
use English '-no_match_vars';

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in XML file

# Read in XML configurations
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent = $xmlObject->XMLin($configurationXMLFile);

# ENV untainting
$ENV{PATH} = '/usr/bin'; # Minimal PATH.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

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

# Rsync call subroutine
# Call using rsync($rsyncUser, $serverName, ($hostConfLocation|$confLocation), $localHostConfDirectory);
sub rsync {
	my $user = $_[0];
	my $server = $_[1];
	my $remoteDirectory = $_[2];
	my $localDirectory = $_[3];
	
	# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
	die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
	if ($pid) {
		while (<KID>) {
			eval {
				'rsync -azCL -e ssh'.
				"$user\@$server:$remoteDirectory/ ".
				"$localDirectory/";
			};
			if ($@) {
				writeError("Cannot execute command 'rsync -azCL -e ssh $user\@$server:$remoteDirectory/ $localDirectory/': $@");
			}
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
		exec 'rsync', '-azCL', '-e ssh', "$user\@$server:$remoteDirectory/", "$localDirectory/" or writeError("Cannot execute command 'rsync -azCL -e ssh $user\@$server:$remoteDirectory/ $localDirectory/': $!");
	}
}

# Access server and rsync virtual host configurations
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	# Skip server if it is disabled
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	
	# Skip server if it's not Linux; no Windows here
	next if $serverReference->{operatingSystem} !~ m/^linux$/i;
	
	my $serverName = $serverReference->{name};
	my $localServerDirectory = "$configurationXMLContent->{localStorageDirectory}/server/$serverName";
	my $rsyncUser = $serverReference->{rsyncUser};
	my $localHostConfDirectory = "$localServerDirectory/hostConf";
	# hostConfLocation > 1 location
	my @hostConfLocation = split(/\s/, $serverReference->{hostConfLocation}) if ($serverReference->{hostConfLocation} =~ m/\s/);
	# hostConfLocation = 1 location
	my $hostConfLocation = $serverReference->{hostConfLocation} if ($serverReference->{hostConfLocation} !~ m/\s/);
	
	# Make directories if they don't exist
	mkdir($localServerDirectory) if !(-e $localServerDirectory);
	mkdir($localHostConfDirectory) if !(-e $localHostConfDirectory);
	
	if (@hostConfLocation) {
		# Multiple rsyncs needed due to multiple conf locations
		rsync($rsyncUser, $serverName, $_, $localHostConfDirectory) foreach @hostConfLocation;
	} else {
		# Only one rsync needed as there is only one conf location
		rsync($rsyncUser, $serverName, $hostConfLocation, $localHostConfDirectory);
	}
	
	# Parse virtual host configurations for essential AWStats information
	
	# Grab names of all files in specified directory
	my @filesInDirectory = glob("$localHostConfDirectory/*");
	
	foreach my $unknownFile (@filesInDirectory) {
		chomp($unknownFile);
		
		# Find only conf files
		my $knownFile;
		if (($unknownFile =~ m/\/([a-zA-Z0-9-]*\.[a-zA-Z0-9-]*\.[a-zA-Z]{2,3})$/) or ($unknownFile =~ m/\/([a-zA-Z0-9-]*\.[a-zA-Z0-9-]*\.[a-zA-Z]{2,3}\.conf)$/)) {
			# Regex matches: www.example.com OR www.example.com.conf
			$knownFile = $1;
		} else {
			next;
		}
		
		# Slurp file for parsing
		my $knownFileContents;
		{ local $/ = undef; local *FILE; open FILE, "<$localHostConfDirectory/$knownFile"; $knownFileContents = <FILE>; close FILE }
		
		# Parse file
		my %virtualHostHash;
		if ($knownFileContents =~ m/ServerName\s([a-zA-Z0-9\.-]*)\s*/) {
			$virtualHostHash{name} = $1;
		} else {
			writeError("$unknownFile - ServerName not defined. Skipped.");
			next;
		}
			
		if ($knownFileContents =~ m/ServerAlias(.*?)\s*[A-Z][a-z]+/ms) {
			my $serverAliasString = $1;
			$serverAliasString =~ s/\s*\\\s*/ /msg; # find all backslashes and remove
			$serverAliasString =~ s/^\s*//msg; # remove whitespace characters at beginning
			$serverAliasString =~ s/\s*$//msg; # remove whitespace characters at end
			$virtualHostHash{hostAlias} = $serverAliasString;
		} else {
			writeError("$unknownFile - ServerAlias not defined. Skipped.");
			next;
		}
		
		if ($knownFileContents =~ m/CustomLog\s(.*)\s(combined|common)\s*/) {
			$virtualHostHash{logFormat} = $2;
			($virtualHostHash{logLocation}, $virtualHostHash{logName}) = $1 =~ m/^(.*)\/(.*)$/;
		} else {
			writeError("$unknownFile - CustomLog not defined. Skipped.");
			next;
		}
		
		if ($knownFileContents =~ m/DocumentRoot\s(.*)\/.*/) {
			$virtualHostHash{hostLocation} = $1;
		} else {
			writeError("$unknownFile - DocumentRoot not defined. Skipped.");
			next;
		}
		
		# Loop virtual hosts on server
		# If host already exists, ensure data is current
		my $virtualHostFound = 0;
		foreach my $virtualHostReference (@{$serverReference->{host}}) {
			if ($virtualHostReference->{name} eq $virtualHostHash{name}) {
				$virtualHostFound = 1;
				last if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
				$virtualHostReference->{hostAlias} = $virtualHostHash{hostAlias};
				$virtualHostReference->{logLocation} = $virtualHostHash{logLocation};
				$virtualHostReference->{logName} = $virtualHostHash{logName};
				$virtualHostReference->{hostLocation} = $virtualHostHash{hostLocation};
				last;
			}
		}
		
		# If not, push new host onto host array
		if ($virtualHostFound == 0) {
			$virtualHostHash{currentlyHosted} = 'True';
			$virtualHostHash{logLastEntryTimestamp} = 'False';
			$virtualHostHash{localLogLocation} = "$localServerDirectory/$virtualHostHash{name}/logs";
			my $virtualHostHashReference = \%virtualHostHash;
			push(@{$serverReference->{host}}, $virtualHostHashReference);
		}
	}
}

# Write to configuration XML
eval {
	$configurationXMLContent = XMLout($configurationXMLContent, KeyAttr => "name");
	open(XML, ">$configurationXMLFile") or die;
	print XML "$configurationXMLContent";
	close(XML) or die;
};
if ($@) {
	writeError("Configuration XML write failed: $@");
}

# Phew, all done
