#!/usr/bin/perl -w
#
# this is an example perl client for the PBXd web service
#

use strict;
use LWP::UserAgent;
use XML::Simple;
local $ENV{XML_SIMPLE_PREFERRED_PARSER} = 'XML::Parser'; # this makes XML::Simple much faster

use Data::Dumper;

my $node = 'n1';
my $command = "display time";

my $ua = LWP::UserAgent->new;
$ua->timeout(5);

#my $extension = '12345';
#my $command = "display station $extension";
#my $request_xml = "<command pbxName='$node' cmdType='ossi' cmd='$command'><field fid='8003ff00'/><field fid='8007ff00'/><field fid='004fff00'/></command>";
#my $request_xml = "<command pbxName='$node' cmdType='ossi' cmd='$command'><field fid='8003ff00'/></command>";

my $request_xml = "<command pbxName='$node' cmdType='ossi' cmd='$command'></command>";
my $request;
$request->{request} = $request_xml;
my $response = $ua->post('https://?your pbxd web proxy host?/pbxd/v2/index.cgi', $request);

if ($response->is_success) {
    my $command_output = XMLin( $response->content,
            ContentKey => 'text',
            ForceArray => [ 'field','ossi_object' ]
            );
    print Dumper($command_output);

    my @ossi_objects;
    foreach my $o ( @{$command_output->{ossi_object}} ) {
        my $fields;
        foreach my $f ( @{$o->{field}} ) {
            $fields->{$f->{fid}} = $f->{text};
        }
        $ossi_objects[ $o->{i} -1 ] = $fields;
    }
    print Dumper(@ossi_objects);

    $command_output->{ossi_object} = \@ossi_objects;
    if ( $command_output->{error} ) {
        print "pbxd error: ". $command_output->{error};
    }
}
else {
    print "pbxd connection failed: ". $response->status_line;
}
