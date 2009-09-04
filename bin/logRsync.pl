#!/usr/bin/perl
# Syncs logs from servers

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
# Call using rsync($rsyncUser, $serverName, $remoteDir, $localDir);
sub rsync {
	my $arg1 = $_[0];
	my $arg2 = $_[1];
	my $arg3 = $_[2];
	my $arg4 = $_[3];
	
	# Taken from Perl Security perldoc page (http://perldoc.perl.org/perlsec.html)
	die "Can't fork: $!" unless defined(my $pid = open(KID, "-|"));
	if ($pid) {
		while (<KID>) {
			eval {
				'rsync -azCL --delete -e ssh '.
				"$arg1\@$arg2:$arg3 ".
				"$arg4/";
			};
			if ($@) {
				writeError("Cannot execute command 'rsync -azCL --delete -e ssh $arg1\@$arg2:$arg3 $arg4/': $@");
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
		exec 'rsync', '-azCL', '--delete', '-e ssh', "$arg1\@$arg2:$arg3", "$arg4/" or writeError("Cannot execute command 'rsync -azCL --delete -e ssh $arg1\@$arg2:$arg3 $arg4/': $!");
	}
}

# Rsync logs to local storage
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	
	my $serverName = $serverReference->{name};
	my $rsyncUser = $serverReference->{rsyncUser};
	
	foreach my $virtualHostReference (@{$serverReference->{host}}) {
		next if ($virtualHostReference->{currentlyHosted} =~ m/^false$/i);
		
		my $virtualHostDirectory = "$configurationXMLContent->{localStorageDirectory}/server/$serverName/$virtualHostReference->{name}";
		my $virtualHostLogDirectory = "$virtualHostDirectory/logs";
		my $remoteDir = "$virtualHostReference->{logLocation}/$virtualHostReference->{logName}*"; # Retrieves all logs with same prefix
		
		mkdir($virtualHostDirectory) if !(-e $virtualHostDirectory);
		mkdir($virtualHostLogDirectory) if !(-e $virtualHostLogDirectory);
		rsync($rsyncUser, $serverName, $remoteDir, $virtualHostLogDirectory);
	}
}