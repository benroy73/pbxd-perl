#!/usr/bin/perl -w

# Author: Benjamin Roy <benroy@uw.edu>
#
# Description: this is a web cgi interface to a group of pbxd servers
#
# Copyright: 2011
# License: Apache 2.0

use strict;
use CGI;
use Data::Dumper;
use XML::Simple;
use IO::Socket;

#my $DEBUG = 1;
my $pbxd_server_hostname = "stooge1";

my $query = new CGI;

my $this_script_name = `basename $0`;
chomp $this_script_name;


#======================================
sub lookup_pbxd_port {
#======================================
    my ($request) = @_;
    my $pbxName = $request->{pbxName};

    # select the correct PeerPort for the desired PBX server
    if    ($pbxName eq 'n1')                  { return 20201; }
    elsif ($pbxName eq 'n2')                  { return 20202; }
    else                                      { return 20200; } #ondemand connection
}

#======================================================================
sub trim($) {
#======================================================================
    my $string = shift;
    if ( $string ne '' ) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
    }
    return $string;
}

#======================================
sub doErrorOutput {
#======================================
    my ($error_message) = @_;
    my $result;
    $result->{error}->{text} = $error_message;

    print $query->header(-type=>'application/xml');
    print XMLout( $result, ContentKey => 'text', RootName => 'command');
    exit(0);
}

#======================================
sub processRequest {
#======================================
    my $request_xml = $query->param('request');
    my $pbxd_port;
    #my $result;

    if ( $query->param('request') eq '' ) {
        doErrorOutput( "Empty request." );
    }

    my $request;
    eval {
        $request = XMLin( $request_xml );
    };
    unless($request) {
        doErrorOutput( "Unable to parse XML request:  $request_xml" );
    }

#    $result->{cmd} = $request->{cmd};
#    $result->{cmdType} = $request->{cmdType};
##	$result->{pbxID} = $request->{pbxID};
#    $result->{pbxName} = $request->{pbxName};


#        unless ( $request->{pbxName} || $request->{pbxID} ) {
#		doErrorOutput( "You must specify a valid pbxName or pbxID." );

    unless ( $request->{pbxName} ) {
        doErrorOutput( "You must specify a valid pbxName." );
    }
    unless ( $pbxd_port = lookup_pbxd_port( $request) ) {
        doErrorOutput( "Unable to lookup a pbxd server port for this PBX." );
    }

    my $sock = new IO::Socket::INET (
        PeerAddr => $pbxd_server_hostname,
        PeerPort => $pbxd_port,
        Proto => 'tcp',
    );
    unless ($sock) {
        doErrorOutput( "Could not connect to pbxd server on $pbxd_server_hostname: $!" );
    };

    my $result_xml = '';
    $sock->autoflush(1);
    print $sock "$request_xml";
    print $sock "\nEND OF REQUEST\n";
    while ( <$sock> ) { $result_xml .= $_ }
    close($sock);

    if ( $result_xml eq '' ) {
        doErrorOutput( "Empty output from pbxd server." );
    }
    else {
        if ($result_xml =~ /Timeout waiting for PBX results/) {
            print $query->header(-status=>'504 Gateway Timeout', -type=>'application/xml');
        }
        elsif ($result_xml =~ /Timeout waiting for client input/) {
            print $query->header(-status=>'408 Request Timeout', -type=>'application/xml');
        }
        else {
            print $query->header(-type=>'application/xml');
        }

        print trim($result_xml);
    }
}

#======================================
sub doUsageInstructions {
#======================================
    print $query->header();
    print <<END_HTML;
<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>pbxd web interface</title>
    <link href='style.css' rel='stylesheet'>
</head>
<body>

<h3>pbxd web interface</h3>

<div class="table">

    <div id="controls" class="cell">
<pre>n1, n2 have preconnected sessions, all other PBX system will be connected on demand.

Usage example:

&lt;command pbxName="n1" cmdType="vt220" cmd="display station 68258" verbose="true"&gt;
&lt;!-- the PBX must be identified with a pbxName --&gt;
&lt;!-- cmdType must be vt220 or ossi --&gt;
   &lt;!-- fields are optional with the ossi cmdType and there can be many.
     They specify the fields to retrieve or change with an OSSI command.
     the field text data is only required to change a field with a change command --&gt;
   &lt;field fid="8003ff00"&gt;68258 Roy, Ben&lt;/field&gt;
   &lt;field fid="004fff00"/&gt;
&lt;/command&gt;
</pre>

        <form method="post" action="$this_script_name">
            Paste the request XML data here.
            <div><textarea name="request" rows="10" cols="74"></textarea></div>
            <input name="submit_test" value="Submit" type="submit">
        </form>

    </div>
</div>

</body>
</html>
END_HTML
}


#======================================
# the main logic for this script
#======================================

# list of parameters passed from the browser
my @param_names = $query->param;

if ( grep $_ eq 'request', @param_names ) {
    processRequest();
}
elsif ( ! defined( $query->param('request') ) ) {
    doUsageInstructions();
}
else {
    doErrorOutput( "It is not clear how you got here. Please notify the developer with as much detail as possible about what steps brought you here." );
}

exit(0);
