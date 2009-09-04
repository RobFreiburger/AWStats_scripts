#!/usr/bin/perl

use strict;
use XML::Simple qw(:strict);
use File::Copy;

# Changeable variables
my $configurationXMLFile = "/srv/stats/etc/configuration.xml";
# Change everything else in XML file

# Read in XML configurations
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent = $xmlObject->XMLin($configurationXMLFile);

foreach my $serverReference (@{$configurationXMLContent->{server}})
{
	foreach my $hostReference (@{$serverReference->{host}})
	{
		my @filesInDirectory = glob("$configurationXMLContent->{localStorageDirectory}/server/$serverReference->{name}/$hostReference->{name}/stats/*");
		
		foreach my $file (@filesInDirectory)
		{
			my $filename = $file;
			$filename =~ s/.*\/(.*)/$1/;
			mkdir("$configurationXMLContent->{localStorageDirectory}/host/$hostReference->{name}") unless -e "$configurationXMLContent->{localStorageDirectory}/host/$hostReference->{name}";
			copy($file, "$configurationXMLContent->{localStorageDirectory}/host/$hostReference->{name}/$filename");
		}
	}
}