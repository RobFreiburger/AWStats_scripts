#!/usr/bin/perl
# Error log emailing and clearing

use strict;
use XML::Simple qw(:strict);
use Mail::Sendmail;

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in XML file
my $doNotEraseLogFile = 1;

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

my $errorLog;
{ local $/ = undef; local *FILE; open FILE, "<$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{errorLog}"; $errorLog = <FILE>; close FILE }

# Email to NOC
my %email;
$email{to} = $configurationXMLContent->{errorEmail};
$email{from} = 'noreply@alliancetechnologies.net';
(my $DAY, my $MONTH, my $YEAR) = (localtime)[3,4,5];
$YEAR += 1900;
$email{subject} = "AWStats Error Log $YEAR-$MONTH-$DAY";
$email{body} = $errorLog;
eval {
	sendmail(%email) or die;
	$doNotEraseLogFile = 0; # Set to False
};
if ($@) {
	writeError("Sendmail failed: $Mail::Sendmail::error");
}

# Wipe registration list
if ($doNotEraseLogFile == 0) {
	open(LOG, ">$configurationXMLContent->{localStorageDirectory}/$configurationXMLContent->{errorLog}"); # Write mode
	print LOG "";
	close(LOG);
} else {
	writeError("Unable to email error log for unknown reason.");
}

return 0;