#!/usr/bin/perl
# Creates the host-server association
# With this script, sites hosted on mulitple servers are accounted for.

use strict;
use XML::Simple qw(:strict);

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in the XML file

# Read in XML file
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent =  $xmlObject->XMLin($configurationXMLFile);

# Add host to root XML level
foreach my $serverReference (@{$configurationXMLContent->{server}}) {
	foreach my $hostReference (@{$serverReference->{host}}) {
		# Skip host if not currently hosted
		next if $hostReference->{currentlyHosted} =~ m/^false$/i;
		
		# See if host is already in root XML level
		my $hostFound = 0;
		foreach my $rootHost (@{$configurationXMLContent->{host}}) {
			next if $hostReference->{name} ne $rootHost->{name};
		
			$hostFound = 1;
						
			# Append $hostAlias to rootHost's hostAlias value if it isn't already there
			foreach my $hostAlias (split(/\s+/, $hostReference->{hostAlias})) {
				$rootHost->{hostAlias} .= " $hostAlias" if $rootHost->{hostAlias} !~ m/$hostAlias/i;
			}
			$rootHost->{hostAlias} =~ s/\s*$//; # get rid of whitespace at end
			
			last;
		}
		
		# Add host to root XML level if not present
		if ($hostFound == 0) {
			my %hostHash;
			$hostHash{name} = $hostReference->{name};
			$hostHash{hostAlias} = $hostReference->{hostAlias};
			$hostHash{currentlyHosted} = 'True';
			$hostHash{localStatsLocation} = "$configurationXMLContent->{localStorageDirectory}/host/$hostHash{name}";
			my $hostHashRef = \%hostHash;
			push(@{$configurationXMLContent->{host}}, $hostHashRef);
			
			mkdir("$configurationXMLContent->{localStorageDirectory}/host/$hostHash{name}") if !(-e "$configurationXMLContent->{localStorageDirectory}/host/$hostHash{name}");
		}
	}
}

# Below this is probably the worst code I've written. So many nested loops.
# Add server to host
foreach my $hostReference (@{$configurationXMLContent->{host}}) {
	next if $hostReference->{currentlyHosted} =~ m/^false$/i;
	
	# Check each server listed in root XML tree
	foreach my $serverReference (@{$configurationXMLContent->{server}}) {
		
		# First, find if host is located on server
		my $hostFound = 0;
		foreach my $serverHostRef (@{$serverReference->{host}}) {
	
			# Find host in server tree
			next if $serverHostRef->{name} ne $hostReference->{name};
			$hostFound = 1;
			
			# Second, find if server is listed under host
			my $serverFound = 0;
			foreach my $hostServerRef (@{$hostReference->{server}}) {
				
				# If server listed under host, keep values current.
				if ($hostServerRef->{name} eq $serverReference->{name}) {
					$serverFound = 1;
					
					# Server information
					$hostServerRef->{operatingSystem} = $serverReference->{operatingSystem};
					$hostServerRef->{rsyncUser} = $serverReference->{rsyncUser};
					$hostServerRef->{serverDisabled} = $serverReference->{serverDisabled};
					
					# Host server-specific information
					$hostServerRef->{hostLocation} = $serverHostRef->{hostLocation};
					$hostServerRef->{localLogLocation} = $serverHostRef->{localLogLocation};
					$hostServerRef->{logFormat} = $serverHostRef->{logFormat};
					$hostServerRef->{logLastEntryTimestamp} = $serverHostRef->{logLastEntryTimestamp};
					$hostServerRef->{logName} = $serverHostRef->{logName};
					
					last;
				}
			}
			last if $serverFound == 1;
			
			# If server not found, time to add it
			my %hostServerHash;
			$hostServerHash{name} = $serverReference->{name};
			$hostServerHash{operatingSystem} = $serverReference->{operatingSystem};
			$hostServerHash{rsyncUser} = $serverReference->{rsyncUser};
			$hostServerHash{serverDisabled} = $serverReference->{serverDisabled};
			$hostServerHash{hostLocation} = $serverHostRef->{hostLocation};
			$hostServerHash{localLogLocation} = $serverHostRef->{localLogLocation};
			$hostServerHash{logFormat} = $serverHostRef->{logFormat};
			$hostServerHash{logLastEntryTimestamp} = $serverHostRef->{logLastEntryTimestamp};
			$hostServerHash{logName} = $serverHostRef->{logName};
			$hostServerHash{currentlyHosted} = 'True';
			my $hostServerHashRef = \%hostServerHash;
			push(@{$hostReference->{server}}, $hostServerHashRef);
			
			last;
		}
		
		# If host not found, go to next server and repeat loop
		next if $hostFound == 0;
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