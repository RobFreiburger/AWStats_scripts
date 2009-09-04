#!/usr/bin/perl
# Compares log last access time and sets flags in configuration XML
# Run after processing logs

use strict;
use XML::Simple qw(:strict);

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in XML file

# Read in XML configurations
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent = $xmlObject->XMLin($configurationXMLFile);

# ENV untainting
$ENV{PATH} = '/usr/bin'; # Minimal PATH.
delete @ENV{ qw(IFS CDPATH ENV BASH_ENV) };

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

# Tagging Apache combined-style logs
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	next if $serverReference->{serverDisabled} =~ m/^true$/i;
	next if $serverReference->{operatingSystem} !~ m/^linux$/i;
	my $serverName = $serverReference->{name};
	
	foreach my $virtualHostReference (@{$serverReference->{host}}) {
		next if $virtualHostReference->{currentlyHosted} =~ m/^false$/i;
		next if $virtualHostReference->{logFormat} !~ m/^combined$/i;
		my $log = "$virtualHostReference->{localLogLocation}/$virtualHostReference->{logName}";
		my $tailLine;
		
		# Skip non-existant and empty logs
		next if !(-e $log);
		next if -z $log;
				
		eval {
			# Taken from http://perldoc.perl.org/5.8.8/perlipc.html#Safe-Pipe-Opens
			open KID_PS, '-|', 'tail', '-n 1', "$log" or die;
			$tailLine = <KID_PS>;
			close KID_PS or die;
			chomp($tailLine);
			# Match timestamps in this format: [30/Mar/2009:07:47:07 -0500]
			if ($tailLine =~ m/\[(\d{2}\/[a-zA-Z]{3}\/\d{4}:\d{2}:\d{2}:\d{2} [+-]\d{4})\]/) {
				$virtualHostReference->{logLastEntryTimestamp} = $1;
			} else {
				$virtualHostReference->{logLastEntryTimestamp} = 'False';
			}
		};
		if ($@) {
			$virtualHostReference->{logLastEntryTimestamp} = 'False';
		}
	}
}

# Eventually put in code for Windows IIS style logs

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