#!/usr/bin/perl

#  -------------------------------------------------------
#                -=- <check_ovhExpiration.pl> -=-
#  -------------------------------------------------------
#
#  Description : a simple perl script to check if any of your
#  OVH services/servers will expire soon
#
# /!\ please be polite with the usage frequency of this script to avoid to saturate the OVH's API. /!\
#
#  Version : 0.2
#  -------------------------------------------------------
#  In :
#     - see the How to use section
#
#  Out :
#     - only print on the standard output 
#
#  Features :
#     - perfdata output
#
#  Fix Me/Todo :
#     - too many things ;) but let me know what do you think about it
#     - use the Nagios lib for the return code
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
# Just run the script as following to see the options and arguments
#	$ ./check_ovhExpiration.pl -h
# ####################################################################

# ####################################################################
# Changelog :
# -----------
#
# --------------------------------------------------------------------
#   Date:11/06/2013   Version:0.2     Author:Erwan Ben Souiden
#   >> add a new option for output
#      + little fix for output
# --------------------------------------------------------------------
#   Date:03/06/2013   Version:0.1     Author:Erwan Ben Souiden
#   >> creation
# ####################################################################

# ####################################################################
#            Don't touch anything under this line!
#        You shall not pass - Gandalf is watching you
# ####################################################################

use strict;
use Getopt::Long qw(:config no_ignore_case);
use SOAP::Lite
 on_fault => sub { my($soap, $res) = @_; die "connexion failed - please check your login and/or your password"; };

# Generic variables
# -----------------
my $version = '0.2';
my $author = 'Erwan Labynocle Ben Souiden';
my $a_mail = 'erwan@aleikoum.net';
my $script_name = 'check_ovhExpiration.pl';
my $verbose_value = 0;
my $version_value = 0;
my $more_value = 0;
my $help_value = 0;
my $perfdata_value = 0;
my $ovh_soapuri = "https://soapi.ovh.com/manager";
my $ovh_soapproxy = "https://www.ovh.com:1664";
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);


# Plugin default variables
# ------------------------
my $display = 'CHECK OVH Expiration -';
my ($ovh_login,$ovh_pwd) = ("","");
my ($critical,$warning,$plugstate) = (10,20,'OK');

GetOptions (
	'U=s' => \ $ovh_login,
	'user=s' => \ $ovh_login,
	'W=s' => \ $ovh_pwd,
	'password=s' => \ $ovh_pwd,
	'V' => \ $version_value,
	'version' => \ $version_value,
	'c=i' => \ $critical,
	'critical=i' => \ $critical,
	'w=i' => \ $warning,
	'warning=i' => \ $warning,
	'h' => \ $help_value,
	'help' => \ $help_value,
	'display=s' => \ $display,
	'D=s' => \ $display,
	'perfdata' => \ $perfdata_value,
	'p' => \ $perfdata_value,
	'more' => \ $more_value,
	'm' => \ $more_value,
	'v' => \ $verbose_value,
	'verbose' => \ $verbose_value
);

&print_usage() if ($help_value);
&print_version() if ($version_value);


# Syntax check of your specified options
# --------------------------------------
print "DEBUG : data provided: $ovh_login:$ovh_pwd\n" if ($verbose_value);
if (($ovh_pwd eq "") or ($ovh_login eq "")) {
	print $display.'one or more following arguments are missing :ovh_login/ovh_pwd'."\n";
	exit $ERRORS{"UNKNOWN"};
}

print "DEBUG : warning threshold : $warning, critical threshold : $critical\n" if ($verbose_value);
if (($critical < 0) or ($warning < 0) or ($critical > $warning)) {
	print $display.'the thresholds - in number of days - must be integers and the critical threshold lower or equal than the warning threshold'."\n";
	exit $ERRORS{"UNKNOWN"};
}


# Core script
# -----------

# init the SOAP
my $soap = SOAP::Lite
                -> uri("$ovh_soapuri")
                -> proxy("$ovh_soapproxy");


# login action
my $result = $soap->call( 'login' => ("$ovh_login", "$ovh_pwd", 'en', 0) );
print "DEBUG : login successfull with $ovh_login / $ovh_pwd\n" if ($verbose_value);
my $session = $result->result();


# ask the API with the method billingGetReferencesToExpired
my $result_critical = $soap->call( 'billingGetReferencesToExpired' => ($session, $critical) );
my $result_warning = $soap->call( 'billingGetReferencesToExpired' => ($session, $warning) );
print "DEBUG : success to retrieve data with the method billingGetReferencesToExpired\n" if ($verbose_value);


# compute how many critical and warning there are
my @return_critical = $result_critical->result();
my @return_warning = $result_warning->result();
my @return_toanalyze;
my $how_many_critical = scalar @{$return_critical[0]};
my $how_many_warning = scalar @{$return_warning[0]};
my $how_toanalyze = 0;
print "DEBUG : the API returns $how_many_critical services/servers which will expire before $critical days\n" if ($verbose_value);
print "DEBUG : the API returns $how_many_warning services/servers which will expire before $warning days\n" if ($verbose_value);


# find the first thing which will expire (only if there is one!)
my $indice = 0;
my ($return_name,$return_date,$return_type,$return_sentence) = ("","","","");

if ($how_many_critical != 0) {
    @return_toanalyze = @return_critical;
    $how_toanalyze = $how_many_critical;
}
elsif (($how_many_warning !=0) and ($how_many_critical == 0)){
    @return_toanalyze = @return_warning;
    $how_toanalyze = $how_many_warning;
}

while ($indice < $how_toanalyze) {
    print "DEBUG : $return_toanalyze[0][$indice]->{name} // $return_toanalyze[0][$indice]->{expired} // $return_toanalyze[0][$indice]->{type}\n" if ($verbose_value);

    if (($return_toanalyze[0][$indice]->{expired} lt $return_date) or ($return_date eq '')){
        $return_date = $return_toanalyze[0][$indice]->{expired};
        $return_type = $return_toanalyze[0][$indice]->{type};
        $return_name = $return_toanalyze[0][$indice]->{name};

        $return_sentence = "the first thing, which will expire, is $return_name - $return_date";
    }

    $indice++;
}

print "DEBUG : the first thing which will expire: $return_name - $return_date - $return_type\n" if (($verbose_value) and ($how_many_warning !=0) and ($how_many_critical !=0));


# logout action
$soap->call( 'logout' => ( $session ) );
print "DEBUG : logout successfull\n" if ($verbose_value);


### Final
$plugstate = "WARNING" if ($how_many_warning >= 1);
$plugstate = "CRITICAL" if ($how_many_critical >= 1);

# format the output print
my $return_print = $display." ".$plugstate." - ";
$return_print .= $how_many_critical." services/servers will expire in ".$critical." days" if ($how_many_critical >= 1);
$return_print .= " and " if (($how_many_warning >= 1) and ($how_many_critical >= 1));
$return_print .= $how_many_warning." services/servers will expire in ".$warning." days" if ($how_many_warning >= 1);
$return_print .= "nothing to renew soon" if ($plugstate eq "OK");
$return_print .= " ".$return_sentence if (($return_sentence) and ($more_value));
$return_print .= " | critical=$how_many_critical warning=$how_many_warning" if ($perfdata_value);

print "$return_print\n";
exit $ERRORS{"$plugstate"};

# ####################################################################
# function 1 :  display the help
# ------------------------------
sub print_usage() {
    print <<EOT;
$script_name version $version by $author

A simple perl script to check if any of your OVH services/servers will expire soon.
----------------------------------------------------------------------------------------------------
/!\\ please be polite with the usage frequency of this script to avoid to saturate the OVH's API. /!\\
----------------------------------------------------------------------------------------------------

Usage: /<path-to>/$script_name -U bsXXXX-ovh -W password [-c 10] [-w 20] [-D "CHECK OVH Expiration -"] [-m]

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -U, --user=STRING
    Specify the OVH login
    no default value
 -W, --password=STRING
    Specify the OVH password
    no default value
 -c, --critical=INT
    Specify a critical threshold
    Number of days before expiration
    default is 10
 -w, --warning=INT
    Specify a warning threshold
    Number of days before expiration
    default is 20
 -m, --more
    To have a longer output
    by default this option is disabled
 -p, --perfdata
    If you want to activate the perfdata output
 -D, --display=STRING
    To modify the output display... 
    default is "CHECK OVH Expiration -"
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
