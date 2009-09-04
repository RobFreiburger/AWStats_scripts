#!/usr/bin/perl -wT
# Dumps the XML tree for debugging usage

use strict;
use Data::Dumper;
use XML::Simple qw(:strict);

# Changeable variables
my $configurationXMLFile = '/srv/stats/etc/configuration.xml';
# Change everything else in the XML file

# Read in XML file
my $xmlObject = XML::Simple->new(ForceArray => [ qw(server host) ], KeyAttr => []);
my $configurationXMLContent =  $xmlObject->XMLin($configurationXMLFile);

print Dumper($configurationXMLContent);