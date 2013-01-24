#!/usr/bin/perl

#  -------------------------------------------------------
#                -=- <check_activeMQ.pl> -=-
#  -------------------------------------------------------
#
#  Description : yet another plugin to check your ActiveMQ
#  instance, by subscribing to a queue and sending and 
#  reading a message.
#
#  Just want to thank Guillaume 'Gkill' Seigneuret to help 
#  me to improve this little script.

#  Version : 0.1
#  -------------------------------------------------------
#  In :
#     - see the How to use section
#
#  Out :
#     - only print on the standard output 
#
#  Features :
#     - x
#
#  Fix Me/Todo :
#     - too many things ;) but let me know what do you think about it
#     - use the Nagios lib for the return code
#     - problem when a service - different from ActiveMQ - listens on
#	the specified port
#
# ####################################################################

# ####################################################################
# GPL v3
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ####################################################################

# ####################################################################
# How to use :
# ------------
#
# 1 - create a ActiveMQ account for nagios, by editing
#     conf/credentials.properties as following:
#	activemq.nagiosUsername=nagios
#	activemq.nagiosPassword=password1
#     
# 2 - create a monitoring queue, typically: /queue/nagios.TestQueue
#
# 3 - then just run the script :
#     $ ./check_activeMQ.pl --help
# ####################################################################

# ####################################################################
# Changelog :
# -----------
#
# --------------------------------------------------------------------
#   Date:23/01/2013   Version:0.1     Author:Erwan Ben Souiden
#   >> creation
#   + catching authentication errors by Guillaume 'Gkill' Seigneuret
# ####################################################################

# ####################################################################
#            Don't touch anything under this line!
#        You shall not pass - Gandalf is watching you
# ####################################################################

use strict;
use Net::Stomp;
use DateTime;
use Getopt::Long qw(:config no_ignore_case);


# Generic variables
# -----------------
my $version = '0.1';
my $author = 'Erwan Labynocle Ben Souiden';
my $a_mail = 'erwan@aleikoum.net';
my $script_name = 'check_activeMQ.pl';
my $verbose_value = 0;
my $version_value = 0;
my $help_value = 0;
#my $perfdata_value = 0;
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# Plugin default variables
# ------------------------
my $display = 'CHECK ACTIVEMQ -';
my ($activemq_host,$activemq_port,$activemq_login,$activemq_pwd,$activemq_ssl,$activemq_timeout) = ("127.0.0.1",61615,"nagios","password1",0,5);
my $activemq_queue = '/queue/nagios.TestQueue';

GetOptions (
    'H=s' => \ $activemq_host,
    'host=s' => \ $activemq_host,
    'P=i' => \ $activemq_port,
    'port=i' => \ $activemq_port,
    'U=s' => \ $activemq_login,
    'user=s' => \ $activemq_login,
    'W=s' => \ $activemq_pwd,
    'password=s' => \ $activemq_pwd,
    'ssl' => \ $activemq_ssl,
    'q=s' => \ $activemq_queue,
    'queue=s' => \ $activemq_queue,
    't=i' => \ $activemq_timeout,
    'timeout=i' => \ $activemq_timeout,
    'V' => \ $version_value,
    'version' => \ $version_value,
    'h' => \ $help_value,
    'help' => \ $help_value,
    'display=s' => \ $display,
    'D=s' => \ $display,
    #'perfdata' => \ $perfdata_value,
    #'perf' => \ $perfdata_value,
    'v' => \ $verbose_value,
    'verbose' => \ $verbose_value
);

&print_usage() if ($help_value);
&print_version() if ($version_value);

# Syntax check of your specified options
# --------------------------------------
print "DEBUG : data provided: $activemq_login:$activemq_pwd\@$activemq_host:$activemq_port\n" if ($verbose_value);
if (($activemq_host eq "") or ($activemq_port eq "") or ($activemq_login eq "") or ($activemq_queue eq "")) {
    print $display.'one or more following arguments are missing :activemq_host/activemq_port/activemq_login'."\n";
    exit $ERRORS{"UNKNOWN"};
}

if (($activemq_port < 0) or ($activemq_port > 65535)) {
    print $display.'the port must be 0 < port < 65535'."\n";
    exit $ERRORS{"UNKNOWN"};
}

print "DEBUG : the activeMQ url is: $activemq_host:$activemq_port" if ($verbose_value);
print " (over ssl)" if ($verbose_value) and ($activemq_ssl);
print " and the targeted queue is: $activemq_queue\n" if ($verbose_value);
print "DEBUG : the activeMQ timeout: $activemq_timeout second(s)\n" if ($verbose_value);


# Connection to the ActiveMQ server
# ---------------------------------
print "DEBUG : trying to connect to $activemq_host:$activemq_port...\n" if ($verbose_value);
my $stomp = Net::Stomp->new( 
	{ 
		hostname => $activemq_host, 
		port => $activemq_port,
		ssl=> $activemq_ssl
	}
) || warn "SSL problem: ".IO::Socket::SSL::errstr();


# Authentication
# --------------
print "DEBUG : trying to authenticate with username: $activemq_login and password: $activemq_pwd...\n" if ($verbose_value);
$stomp->connect(
	{
		login => "$activemq_login",
		passcode => "$activemq_pwd"
	}
) || warn "SSL problem: ".IO::Socket::SSL::errstr();

die "$display authentication failure for user $activemq_login, please check the password\n" if not defined($stomp->{'session_id'});


# Sending Message
# ---------------
my $dt_now = DateTime->now;
my $activemq_mymsg = 'this is a message for the Nagios Check - '.$dt_now;
print "DEBUG : trying to send the following message into $activemq_queue: \"$activemq_mymsg\"...\n" if ($verbose_value);

$stomp->send_transactional(
	{
	  destination	=> "$activemq_queue",
	  projectId	=>' testId',
	  JMSType	=> "processTask",
	  body 		=> "$activemq_mymsg",
	} 
) or die "$display CRITICAL - impossible to send the message to the queue $activemq_queue\n";


# Subscribe to the queue
# ----------------------
print "DEBUG : trying to subscribe to $activemq_queue...\n" if ($verbose_value);

$stomp->subscribe(
      {   destination             => "$activemq_queue",
          'ack'                   => 'client',
          'activemq.prefetchSize' => 1
      }
);


# Read a message
# --------------
my $can_read = $stomp->can_read({ timeout => "$activemq_timeout" });
if ( $can_read ) {
    my $frame = $stomp->receive_frame or die "$display Couldn't receive the message!";
    $stomp->ack( { frame => $frame } );
    my $framebody=$frame->body;
    print "DEBUG : receiving from $activemq_queue the following message: \"$framebody\"...\n" if ($verbose_value);
    
    #if ( $framebody eq "this is a message for the Nagios Check - $dt_now" ) {
    if ( $framebody eq $activemq_mymsg ) {
        print "$display OK - Message received\n";
    }
    else {
        print "$display WARNING - Incorrect message body; is \"$framebody\" and should be: \"$activemq_mymsg\"\n";
        exit $ERRORS{"WARNING"};
    }
}
else {
    print "$display CRITICAL - Timed out while trying to collect the message\n";
    exit $ERRORS{"CRITICAL"};
}


# Disconnection
# -------------
$stomp->disconnect;


exit $ERRORS{"OK"};


# ####################################################################
# function 1 :  display the help
# ------------------------------
sub print_usage() {
    print <<EOT;
$script_name version $version by $author

Yet another plugin to check your ActiveMQ instance, by subscribing to a queue and sending 
and reading a message.

Usage: /<path-to>/$script_name -H activemq.mydomain.com -P 1234 -U nagios -W password1 --queue /test/Monitoring [-v] [--ssl] [-t 5] 

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -H, --host=STRING
    Specify the ActiveMQ host
    default is 127.0.0.1
 -P, --port=INTEGER
    Specify the ActiveMQ port
    default is 61615
 -U, --user=STRING
    Specify the ActiveMQ username
    default is nagios
 -W, --password=STRING
    Specify the ActiveMQ password
    default is password1
 -q, --queue=STRING
    Specify the monitoring queue
 --ssl
    Enable SSL connection
 -t, --timeout=STRING
    Specify the timeout to retrieve a message from the monitoring queue
    default is 5 seconds
 -D, --display=STRING
    To modify the output display... 
    default is "CHECK ACTIVEMQ -"
 -v, --verbose
    Show details for command-line debugging (Nagios may truncate the output)
    
Send email to $a_mail if you have questions
regarding use of this software. To submit patches or suggest improvements,
send email to $a_mail
This plugin has been created by $author

Hope you will enjoy it ;)

Remember :
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.


EOT
    exit $ERRORS{"UNKNOWN"};
}



# function 2 :  display version information
# -----------------------------------------
sub print_version() {
    print <<EOT;
$script_name version $version
EOT
    exit $ERRORS{"UNKNOWN"};
}
