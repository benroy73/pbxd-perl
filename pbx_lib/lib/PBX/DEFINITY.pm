package PBX::DEFINITY;
our $VERSION = '1.00';

=head1 NAME

PBX::DEFINITY - an XML interface to the Avaya PBX console

=head1 DESCRIPTION

    This module provided access to the ossi interface of an
    Avaya Communication Manager telephone system (aka a Definity PBX).
    Any PBX command available from the SAT terminal can be used.

    The ossi interface is intended as a programmer's interface.
    Interactive users should use the VT220 or 4410 terminal types instead.

    Normally you will want to use the pbx_command method.
    If you want formatted screen capture use the pbx_vt220_command method.

    The xml config file should be located in home directory in the file pbx_connection_auth.xml.
    The format of the config file is:
    <pbx-systems>
        <pbx name='n1'   hostname='localhost' port='22' login='login1'  password='pass1'   connection_type='ssh' atdt='' />
        <pbx name='n2'   hostname='127.0.0.1' port='22' login='login2'  password='pass2'   connection_type='ssh' atdt='' />
    </pbx-systems>

    connection_type can be ssh, ssl or telnet
    if you need to dial a modem or data module then the number to dial goes in the atdt field

=head1 EXAMPLES

 use PBX::DEFINITY;
 my $DEBUG = 1;
 my $node = new PBX::DEFINITY('n1', $DEBUG);
 unless( $node && $node->status_connection() ) {
 	die("ERROR: Login failed for ". $node->get_node_name() );
 }

 my %fields = ('0003ff00' => '');
 $node->pbx_command("display time", %fields );
 if ( $node->last_command_succeeded() ) {
 	my @ossi_output = $node->get_ossi_objects();
 	my $hash_ref = $ossi_output[0];
 	print "The PBX says the year is ". $hash_ref->{'0003ff00'} ."\n";
 }

 $node->pbx_command("status station 68258");
 if ( $node->last_command_succeeded() ) {
 	my @ossi_output = $node->get_ossi_objects();
 	my $i = 0;
 	foreach my $hash_ref(@ossi_output) {
 		$i++;
 		print "output result $i\n";
 		for my $field ( sort keys %$hash_ref ) {
 			my $value = $hash_ref->{$field};
 			print "\t$field => $value\n";
 		}
 	}
 }

 if ( $node->pbx_vt220_command('status logins') ) {
 	print $node->get_vt220_output();
 }

 $node->do_logoff();

=head1 AUTHOR

Benjamin Roy <benroy@uw.edu>

=head1 VERSION

$Id: $

=head1 LOCATION

$URL: $

=cut

use strict;

use Expect;
use Term::VT102;
use XML::Simple;
use Data::Dumper;
local $ENV{XML_SIMPLE_PREFERRED_PARSER} = 'XML::Parser';  # this is the fastest parser

$Expect::Debug         = 0;
$Expect::Exp_Internal  = 0;
$Expect::Log_Stdout    = 0;  #  STDOUT ...

use constant PBX_CONFIG_FILE => 'pbx_connection_auth.xml';
use constant TERMTYPE        => 'ossi4';  # options are ossi, ossi3, or ossi4
use constant TIMEOUT         => 60;

my $DEBUG = 0;

my $telnet_command  = '/usr/bin/telnet';
my $ssh_command     = '/usr/local/bin/ssh';
my $openssl_command = '/usr/bin/openssl s_client -quiet -connect';


#=============================================================
sub new {
#=============================================================
    my($class, @param) = @_;
    my $self = {};  # Create the anonymous hash reference to hold the object's data.
    bless $self, ref($class) || $class;

    if ($self->_initialize(@param)){
        return($self);
    }
    else {
        return(0);
    }
}

#=============================================================
sub _initialize {
#=============================================================
    my ($self, $nodename, $debug_param) = @_;

    if ( $debug_param ) {
        $DEBUG = $debug_param;
    }

    ${$self->{'DEBUG'}}         = $DEBUG;
    @{$self->{'DEBUG_LOG'}}	= ();
    ${$self->{'ERRORMSG'}}      = '';
    ${$self->{'CONNECTED'}}     = 0;
    ${$self->{'LAST_COMMAND_SUCCEEDED'}} = 0;

    ${$self->{'VT220_OUTPUT'}}  = '';
    @{$self->{'VT220_SCREENS'}} = ();
    @{$self->{'OSSI_OBJECTS'}}  = ();

    $self->debug_message_log("getting connection parameters for $nodename");

    my $config = XMLin( "$ENV{HOME}/" . PBX_CONFIG_FILE );
    if ( defined $config->{'pbx'}->{$nodename} ) {
        my $pbx = $config->{'pbx'}->{$nodename};

        ${$self->{'NODENAME'}}        = $nodename;
        ${$self->{'HOSTNAME'}}        = $pbx->{'hostname'};
        ${$self->{'PORT'}}            = $pbx->{'port'};
        ${$self->{'USERNAME'}}        = $pbx->{'login'};
        ${$self->{'PASSWORD'}}        = $pbx->{'password'};
        ${$self->{'CONNECTION_TYPE'}} = $pbx->{'connection_type'};
        ${$self->{'ATDT'}}            = $pbx->{'atdt'};

        $self->debug_message_log("loaded $nodename config");
    }
    else {
        my $msg = "ERROR: unknown PBX [$nodename]. Config must be added to config file ". PBX_CONFIG_FILE ." before it can be used in production.";
        print "$msg\n";
        $self->debug_message_log($msg);
        ${$self->{'ERRORMSG'}} = $msg;
        return(0);
    }

    ${$self->{'SESSION'}} = $self->init_session(
                                        ${$self->{'HOSTNAME'}},
                                        ${$self->{'PORT'}},
                                        ${$self->{'USERNAME'}},
                                        ${$self->{'PASSWORD'}},
                                        ${$self->{'CONNECTION_TYPE'}},
                                        ${$self->{'ATDT'}}
                                    );

    return(1);
}

#=============================================================
sub init_session {
#=============================================================
    my ($self, $host, $port, $username, $password, $connection_type, $atdt) = @_;

    my $success = 0;

    my $s = new Expect;
    $s->raw_pty(1);
    $s->restart_timeout_upon_receive(1);

    my $command;
    if ( $connection_type eq 'telnet' ) {
        $command = "$telnet_command $host $port";
    }
    elsif ( $connection_type eq 'ssh' ) {
        $command = "$ssh_command -o \"StrictHostKeyChecking no\" -p $port -l $username $host";
    }
    elsif ( $connection_type eq 'ssl' ) {
        $command = "$openssl_command $host:$port";  #  Somehow the data module and telnet do not mix
    }
    else {
        $self->append_error_message("ERROR: unhandled connection type requested. [$connection_type]");
        return(0);
    }

    $self->debug_message_log("$command");
    $s->spawn($command);

    if (defined $s) {
        $success = 0;
        $s->expect(TIMEOUT,
            [ 'OK', sub {
                    $self->debug_message_log("DEBUG Sending: 'ATDT $atdt'");
                    my $exp = shift;
                    print $exp "ATDT $atdt\n\r";
                    exp_continue;
            } ],
            [ 'WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED', sub {
                    my $msg = "ERROR: ssh remote host key has changed please update ~/.ssh/known_hosts.\n$command";
                    print "$msg\n";
                    $self->debug_message_log($msg);
                    $self->append_error_message($msg);
            }],
            [ 'BUSY', sub {
                    $self->append_error_message("ERROR: The phone number was busy.");
            } ],
            [ 'Login resources unavailable', sub {
                    $self->append_error_message("ERROR: No ports available.");
            }],
            [ '-re', '[Ll]ogin:|[Uu]sername:', sub {
                    my $exp = shift;
                    $self->debug_message_log("Login: $username");
                    print $exp "$username\r";
                    exp_continue;
            }],
            [ 'Password:', sub {
                    my $exp = shift;
                    $self->debug_message_log("entering password");
                    print $exp "$password\r";
                    exp_continue;
            }],
            [ 'Terminal Type', sub {
                    my $exp = shift;
                    $self->debug_message_log("entering terminal type ".TERMTYPE);
                    print $exp TERMTYPE . "\r";
                    exp_continue;
            }],
            [ '-re', '^t$', sub {
                    $self->debug_message_log("connection established");
                    $success = 1;
            }],
            [  eof => sub {
                    $self->append_error_message("ERROR: Connection failed with EOF at login.");
            }],
            [  timeout => sub {
                    $self->append_error_message("ERROR: Timeout on login.");
            }]
        );

        if (! $success) {
            return(0);
        }
        else {
            #  Verify command prompt ...
            sleep(1);
            print $s "\rt\r";
            $s->expect(TIMEOUT,
                [ '-re', 'Terminator received but no command active\nt\012'],
                [  eof => sub {
                        $success = 0;
                        $self->append_error_message("ERROR: Connection failed with EOF at verify command prompt.");
                }],
                [  timeout => sub {
                        $success = 0;
                        $self->append_error_message("ERROR: Timeout on verify command prompt.");
                }],
                [ '-re', '^t$', sub {
                        exp_continue;
                }]
            );
            if ($success) {
                    $self->set_connected();
            } else {
                    return(0);
            }
        }
    } else {
        $self->append_error_message("ERROR: Could not create an Expect object.");
    }
    return($s);
}

#======================================================================
sub do_logoff {
#======================================================================
    my ($self) = @_;
    my $session = ${$self->{'SESSION'}};
    if ( $session ) {
        $session->send("c logoff \rt\r");
        $session->expect(TIMEOUT,
            [ qr/NO CARRIER/i ],
            [ qr/Proceed With Logoff/i, sub { my $self = shift; $self->send("y\r"); } ],
            [ qr/onnection closed/i ] );
        $session->soft_close();
        $self->debug_message_log("PBX connection disconnected");
    }
    return(0);
}


#======================================================================
#
# submit a command to the PBX and return the result
# fields can be specified to return only the fields desired
# data values for the fields can be included for "change" commands
#
# a good way to identify field id codes is to use a "display" command and
# compare it to the output of the same command to a VT220 terminal
# for example to see all the fields for a change station you could call this
# function with a "display station" and no field list like this:
#  $node->pbx_command("display station");
#
sub pbx_command {
#======================================================================
    my ($self, $command, %fields) = @_;
    my $ossi_output = {};
    my $this = $self;
    my $session = ${$self->{'SESSION'}};
    my @field_ids;
    my @field_values;
    my $cmd_fields = '';
    my $cmd_values = '';
    my $command_succeeded = 1;
    $self->{'ERRORMSG'} = ''; #reset the error message
    @{$self->{'OSSI_OBJECTS'}} = (); #reset the objects array

    $self->debug_message_log("DEBUG Processing pbx_command($command, \%fields)");
    $self->debug_message_log("DEBUG \%fields contains:");
    $self->debug_message_log(Dumper(%fields));

    for my $field ( sort keys %fields ) {
        my $value = $fields{$field};
        $cmd_fields .= "$field\t";
        $cmd_values .= "$value\t";
    }
    chop $cmd_fields; # remove the trailing \t character
    chop $cmd_values;

    $session->send("c $command\r");
    $self->debug_message_log("DEBUG Sending \nc $command");
    if ( $cmd_fields ne '' ) {
        $session->send("f$cmd_fields\r");
        $self->debug_message_log("f$cmd_fields");

        $session->send("d$cmd_values\r");
        $self->debug_message_log("d$cmd_values");
    }
    $session->send("t\r");
    $self->debug_message_log("t");

    $session->expect(TIMEOUT,
    [ '-re', '^f.*\x0a', sub {
        my $exp = shift;
        my $a = trim( $exp->match() );
        $self->debug_message_log("DEBUG Matched '$a'");
        $a =~ s/^f//;  # strip the leading 'f' off
        my ($field_1, $field_2, $field_3, $field_4, $field_5) = split(/\t/, $a, 5);
        #print "field_ids are: $field_1|$field_2|$field_3|$field_4|$field_5\n" if ($DEBUG);
        push(@field_ids, $field_1);
        push(@field_ids, $field_2);
        push(@field_ids, $field_3);
        push(@field_ids, $field_4);
        push(@field_ids, $field_5);
        exp_continue;
    } ],
    [ '-re', '^[dent].*\x0a', sub {
        my $exp = shift;
        my $a = trim( $exp->match() );
        $self->debug_message_log("DEBUG Matched '$a'");

        if ( trim($a) eq "n" || trim($a) eq "t" ) { # end of record output
            # assign values to $ossi_output object
            for (my $i = 0; $i < scalar(@field_ids); $i++) {
                if ( $field_ids[$i] ) {
                    $ossi_output->{$field_ids[$i]} = $field_values[$i];
                }
            }
            #	print Dumper($ossi_output) if $DEBUG;
            delete $ossi_output->{''}; # I'm not sure how this get's added but we don't want it.
            push(@{$this->{'OSSI_OBJECTS'}}, $ossi_output);
            @field_values = ();
            undef $ossi_output;
        }
        elsif ( substr($a,0,1) eq "d" ) { # field data line
            $a =~ s/^d//;  # strip the leading 'd' off
            my ($field_1, $field_2, $field_3, $field_4, $field_5) = split(/\t/, $a, 5);
            #	print "field_values are: $field_1|$field_2|$field_3|$field_4|$field_5\n" if ($DEBUG);
            push(@field_values, $field_1);
            push(@field_values, $field_2);
            push(@field_values, $field_3);
            push(@field_values, $field_4);
            push(@field_values, $field_5);
        }
        elsif ( substr($a,0,1) eq "e" ) { # error message line
            $a =~ s/^e//;  # strip the leading 'd' off
            my ($field_1, $field_2, $field_3, $field_4) = split(/ /, $a, 4);
            my $mess = $field_4;
            $self->debug_message_log("ERROR: field $field_2 $mess");
            $this->{'ERRORMSG'} .= "$field_2 $mess\n";
            $command_succeeded = 0;
        }
        else {
            #print "ERROR: unknown match \"" . $self->match() ."\"\n";
            $self->debug_message_log("ERROR: unknown match \"" . $self->match() ."\"");
        }

        unless ( trim($a) eq "t" ) {
            exp_continue;
        }
    } ],
    [  eof => sub {
        $command_succeeded = 0;
        my $msg = "ERROR: Connection failed with EOF in pbx_command($command).";
        $self->debug_message_log($msg);
        $this->{'ERRORMSG'} .= $msg;
    } ],
    [  timeout => sub {
        $command_succeeded = 0;
        my $msg = "ERROR: Timeout in pbx_command($command).";
        $self->debug_message_log($msg);
        $this->{'ERRORMSG'} .= $msg;
    } ],
    );

    if ( $command_succeeded ) {
        $this->{'LAST_COMMAND_SUCCEEDED'} = 1;
        return(1);
    }
    else {
        $this->{'LAST_COMMAND_SUCCEEDED'} = 0;
        return(0);
    }
}


#======================================================================
#
# capture the VT220 terminal screen output of a PBX command
#
sub pbx_vt220_command {
#======================================================================
    my ($self, $command) = @_;
    my $session = ${$self->{'SESSION'}};
    my $command_succeeded = 1;
    $self->{'ERRORMSG'} = ''; #reset the error message

    $self->{'VT220_OUTPUT'} = '';
    @{$self->{'VT220_SCREENS'}} = ();
    my $command_output = '';
    my $ESC         = chr(27);      #  \x1b
    my $CANCEL      = $ESC . "[3~";
    my $NEXT        = $ESC . "[6~";

#4410 keys
#F1=Cancel=<ESC>OP
#F2=Refresh=<ESC>OQ
#F3=Save=<ESC>OR
#F4=Clear=<ESC>OS
#F5=Help=<ESC>OT
#F6=GoTo=<ESC>Or  ...OR... F6=Update=<ESC>OX  ...or.... F6=Edit=<ESC>f6
#F7=NextPg=<ESC>OV
#F8=PrevPg=<ESC>OW

#VT220 keys
#Cancel          ESC[3~      F1
#Refresh         ESC[34~     F2
#Execute         ESC[29~     F3
#Clear Field     ESC[33~     F4
#Help            ESC[28~     F5
#Update Form     ESC[1~      F6
#Next Page       ESC[6~      F7
#Previous Page   ESC[5~      F8

    unless ( $self->status_connection() ) {
        $self->{'ERRORMSG'} .= 'ERROR: No connection to PBX.';
        $self->{'LAST_COMMAND_SUCCEEDED'} = 0;
        return(0);
    }

    # switch the terminal type from ossi to VT220
    $session->send("c newterm\rt\r");
    $self->debug_message_log("DEBUG switching to VT220 terminal type");

    $session->expect(TIMEOUT,
        [ 'Terminal Type', sub {
            $session->send("VT220\r");
            $self->debug_message_log("DEBUG sending VT220");
            exp_continue;
        }],
        [ '-re', 'Command:', sub {
            $self->debug_message_log("DEBUG ready for next command.");
        }],
        [  timeout => sub {
            $self->append_error_message("ERROR: Timeout switching to VT220 terminal type.");
        }]
    );

    $session->send("$command\r");
    $self->debug_message_log("DEBUG Sending $command");

    $session->expect(TIMEOUT,
        [ '-re', '\x1b\[\d;\d\dH\x1b\[0m|\[KCommand:|press CANCEL to quit --  press NEXT PAGE to continue|Command successfully completed', sub {
            # end of screen
            #\[24;1H\x1b\[KCommand:

            my $string = $session->before();
            $string =~ s/\x1b/\n/gm;
            $self->debug_message_log("DEBUG \$session->before()\n$string");

            #my $string = $session->before();
            #$string =~ s/\x1b/\n/gm;
            #print "Expect end of page\n$string\n";
            my $a = trim( $session->match() );
            $self->debug_message_log("DEBUG \$session->match() '$a'");
            my $current_page = 0;
            my $page_count = 1;
            if ( $session->before() =~ /Page +(\d*) of +(\d*)/ ) {
                $current_page = $1;
                $page_count = $2;
            }
            $self->debug_message_log("DEBUG on page $current_page out of $page_count pages");
            my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
            $vt->process( $session->before() );
            my $row = 0;
            my $screen;
            while ( $row < $vt->rows() ) {
                my $line = $vt->row_plaintext($row);
                $screen .= "$line\n" if $line;
                $row++;
            }
            $self->debug_message_log($screen);
            push( @{$self->{'VT220_SCREENS'}}, $screen);
            $command_output .= $screen;
            if ( $session->match() eq 'Command successfully completed') {
                $self->debug_message_log("DEBUG \$session->match() is 'Command successfully completed'");
            }
            elsif ( $session->match() eq '[KCommand:') {
                $self->debug_message_log("DEBUG returned to 'Command:' prompt");
                if ( $session->after() ne ' ' ) {
                    $self->debug_message_log("DEBUG \$session->after(): '". $session->after() ."'");

                    my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
                    $vt->process( $session->before() );
                    $self->append_error_message("ERROR: ". $vt->row_plaintext(23));

                    $session->send("$CANCEL");
                    $command_succeeded = 0;
                }
            }
            elsif ($current_page == $page_count) {
                $self->debug_message_log("DEBUG received last page. command finished");
                $session->send("$CANCEL");
            }
            elsif ($current_page < $page_count ) {
                $self->debug_message_log("DEBUG requesting next page");
                $session->send("$NEXT");
                exp_continue;
            }
            else {
                $self->debug_message_log("ERROR: unknown condition");
            }
        }],
        [  eof => sub {
            $command_succeeded = 0;
            $self->append_error_message("ERROR: Connection failed with EOF in pbx_vt220_command($command).");
        } ],
        [  timeout => sub {
            $command_succeeded = 0;
            my $string = $session->before();
            $string =~ s/\x1b/\n/gm;
            $self->debug_message_log("ERROR: timeout in pbx_vt220_command($command)\n\$session->before()\n$string");

            my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
            $vt->process( $session->before() );
            $self->append_error_message("ERROR: ". $vt->row_plaintext(23));

            $session->send("$CANCEL");
        } ],
    );

    # switch back to the original ossi terminal type
    $self->debug_message_log("DEBUG switching back to ossi terminal type");
    $session->send("$CANCEL");
    $session->send("newterm\r");
    $self->debug_message_log("DEBUG sending cancel and newterm");
    $session->expect(TIMEOUT,
        [ 'Terminal Type', sub {
            $session->send(TERMTYPE . "\r");
            $self->debug_message_log("DEBUG sending ". TERMTYPE);
            exp_continue;
        }],
        [ '-re', '^t$', sub {
            $self->debug_message_log("DEBUG ready for next command");
        }],
        [  timeout => sub {
            $self->append_error_message("ERROR: Timeout while switching back to ossi terminal.");
        }]
    );

    if ( $command_succeeded ) {
        $self->{'VT220_OUTPUT'} = $command_output;
        $self->{'LAST_COMMAND_SUCCEEDED'} = 1;
        return(1);
    }
    else {
        $self->{'LAST_COMMAND_SUCCEEDED'} = 0;
        return(0);
    }

}


#=============================================================
sub trim($) {
#=============================================================
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

#=============================================================
sub append_error_message {
#=============================================================
    my ($self, $msg) = @_;
    $self->debug_message_log("DEBUG: $msg");
    $self->{'ERRORMSG'} .= $msg;
}

#=============================================================
sub set_debug_state {
#=============================================================
    my ($self, $debug_value) = @_;
    @{$self->{'DEBUG_LOG'}} = (); #reset debug log
    if ($debug_value == 1) {
        ${$self->{'DEBUG'}} = 1;
    }
    else {
        ${$self->{'DEBUG'}} = 0;
    }
}

#=============================================================
sub debug_message_log {
#=============================================================
    my ($self, $debug_message) = @_;
    push(@{$self->{'DEBUG_LOG'}}, $debug_message) if ${$self->{'DEBUG'}};
}

#=============================================================
sub get_debug_message_log {
#=============================================================
    my ($self) = @_;
    my $debug_log = '';
    for my $msg (@{$self->{'DEBUG_LOG'}}) {
        $debug_log .= "$msg\n" if defined $msg;
    }
    return $debug_log;
}

#=============================================================
sub get_last_error_message {
#=============================================================
    my ($self) = @_;
    return( $self->{'ERRORMSG'} );
}

#=============================================================
sub last_command_succeeded {
#=============================================================
    my ($self) = @_;
    return( $self->{'LAST_COMMAND_SUCCEEDED'} );
}

#=============================================================
sub get_ossi_objects {
#=============================================================
    my ($self) = @_;
    return( @{$self->{'OSSI_OBJECTS'}} );
}

#=============================================================
sub get_vt220_output {
#=============================================================
    my ($self) = @_;
    return( $self->{'VT220_OUTPUT'} );
}

#=============================================================
sub get_vt220_screens {
#=============================================================
    my ($self) = @_;
    return( @{$self->{'VT220_SCREENS'}} );
}

#=============================================================
sub get_node_name {
#=============================================================
    my ($self) = @_;
    return( ${$self->{'NODENAME'}} );
}

#=============================================================
sub set_connected {
#=============================================================
    my ($self) = @_;
    ${$self->{'CONNECTED'}} = 1;
}

#=============================================================
sub unset_connected {
#=============================================================
    my ($self) = @_;
    ${$self->{'CONNECTED'}} = 0;
}

#=============================================================
sub status_connection {
#=============================================================
    my ($self) = @_;
    return( ${$self->{'CONNECTED'}} );
}

1;
