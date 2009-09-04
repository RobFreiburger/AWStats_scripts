#!/usr/bin/perl
# Runs AWStats processing for servers

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

# Run AWStats for each server
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	
	my $serverName = $serverReference->{name};
	my $serverDirectory = "$configurationXMLContent->{localStorageDirectory}/server/$serverName";
	
	foreach my $virtualHostReference (@{$serverReference->{host}}) {
		next if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
				
		my $hostName = $virtualHostReference->{name};
		my $hostLog = "$virtualHostReference->{localLogLocation}/$virtualHostReference->{logName}";
		next if (!(-e $hostLog));
				
		mkdir("$serverDirectory/$hostName/stats") if !(-e "$serverDirectory/$hostName/stats");
		
		# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
		die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
		if ($pid) {
			while (<KID>) {
				"$configurationXMLContent->{AWStatsScriptLocation} -update ".
				"-config=$hostName ".
				"-configdir=$serverDirectory/$hostName";
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
			exec "$configurationXMLContent->{AWStatsScriptLocation}", '-update', "-config=$hostName", "-configdir=$serverDirectory/$hostName" or writeError("Cannot execute command '$configurationXMLContent->{AWStatsScriptLocation} -update -config=$hostName -configdir=$serverDirectory/$hostName': $!");
		}
	}	
}