#!/usr/bin/perl

#  -------------------------------------------------------
#                -=- <check_postgresql.pl> -=-
#  -------------------------------------------------------
#
#  Description : a simple perl script to test if a PostgreSQL
#  instance is up or not + to monitore the number of
#  waiting queries
#
#  Version : 0.1
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
# 1 - create a special monitoring postgreSQL account
#	createuser -D -R -S -P nagios
#
# 2 - don't forget to have a line like this one to your pg_hba.conf 
#	hostssl  all             all             0.0.0.0/0               password
#     thus you can connect to your PostgreSQL instance for anywhere
# 
# 3 - run the script
#	$ ./check_postgresql.pl -h
# ####################################################################

# ####################################################################
# Changelog :
# -----------
#
# --------------------------------------------------------------------
#   Date:24/01/2013   Version:0.1     Author:Erwan Ben Souiden
#   >> creation
# ####################################################################

# ####################################################################
#            Don't touch anything under this line!
#        You shall not pass - Gandalf is watching you
# ####################################################################

use strict;
use Getopt::Long qw(:config no_ignore_case);
use DBI;


# Generic variables
# -----------------
my $version = '0.1';
my $author = 'Erwan Labynocle Ben Souiden';
my $a_mail = 'erwan@aleikoum.net';
my $script_name = 'check_postgresql.pl';
my $verbose_value = 0;
my $version_value = 0;
my $help_value = 0;
my $perfdata_value = 0;
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);


# Plugin default variables
# ------------------------
my $display = 'CHECK PostgreSQL -';
my $status = 'UNKNOWN';
my ($postgres_host,$postgres_port,$postgres_login,$postgres_pwd,$postgres_dbname) = ("127.0.0.1",5432,"nagios","password","template1");
my $postgres_request = 'SELECT 1';
my $postgres_type_request = 'isAlive';
my ($critical,$warning) = (5,2);

GetOptions (
	'H=s' => \ $postgres_host,
	'host=s' => \ $postgres_host,
	'P=i' => \ $postgres_port,
	'port=i' => \ $postgres_port,
	'U=s' => \ $postgres_login,
	'user=s' => \ $postgres_login,
	'W=s' => \ $postgres_pwd,
	'password=s' => \ $postgres_pwd,
	'B=s' => \$postgres_dbname, 
	'database=s' => \$postgres_dbname, 
	'type=s' => \$postgres_type_request,
	't=s' => \$postgres_type_request,
	'V' => \ $version_value,
	'version' => \ $version_value,
	'h' => \ $help_value,
	'help' => \ $help_value,
	'display=s' => \ $display,
	'D=s' => \ $display,
	'perfdata' => \ $perfdata_value,
	'p' => \ $perfdata_value,
	'v' => \ $verbose_value,
	'verbose' => \ $verbose_value
);

&print_usage() if ($help_value);
&print_version() if ($version_value);


# Syntax check of your specified options
# --------------------------------------
print "DEBUG : data provided: $postgres_login:$postgres_pwd\@$postgres_host:$postgres_port\n" if ($verbose_value);
if (($postgres_host eq "") or ($postgres_port eq "") or ($postgres_login eq "")) {
	print $display.'one or more following arguments are missing :postgres_host/postgres_port/postgres_login'."\n";
	exit $ERRORS{$status};
}

if (($postgres_port < 0) or ($postgres_port > 65535)) {
	print $display.'the port must be 0 < port < 65535'."\n";
	exit $ERRORS{$status};
}

print "DEBUG : warning threshold : $warning, critical threshold : $critical\n" if ($verbose_value);
if (($critical < 0) or ($warning < 0) or ($critical < $warning)) {
	print $display.'the thresholds must be integers and the critical threshold higher or equal than the warning threshold'."\n";
	exit $ERRORS{"UNKNOWN"};
}

print "DEBUG : postgres_type_request: $postgres_type_request\n" if ($verbose_value);
if (($postgres_type_request ne 'waintingQueries') and ($postgres_type_request ne 'isAlive')) {
	print $display.'type of request must be waitingQueries or isAlive'."\n";
	exit $ERRORS{"UNKNOWN"};
}
$postgres_request = 'SELECT waiting FROM pg_stat_activity WHERE waiting=true' if ($postgres_type_request eq 'waintingQueries');
print "DEBUG : request to launch: $postgres_request\n" if ($verbose_value);


# Core script
# -----------

# Connection to the database
my $dbh_to_test = DBI->connect("dbi:Pg:dbname=$postgres_dbname;host=$postgres_host;port=$postgres_port",$postgres_login,$postgres_pwd,{AutoCommit => 1, RaiseError => 1, PrintError => 0});
if (! $dbh_to_test) {
	print $display.' UNKNOWN - impossible to connect on '.$postgres_login.'@'.$postgres_host.':'.$postgres_port.' on database '.$postgres_dbname."\n";
	exit $ERRORS{$status};
}

if ($dbh_to_test->ping) {
	
	# Launch the query
	my $sth_to_test = $dbh_to_test->prepare($postgres_request);
	$sth_to_test->execute();
	$status = 'OK';
	
	if ($postgres_type_request eq 'waintingQueries') {
		$status = 'WARNING' if ($sth_to_test->rows >= $warning);
		$status = 'CRITICAL' if ($sth_to_test->rows >= $critical);
		print $display.' '.$status.' - '.$sth_to_test->rows.' queries detected as waiting';
		print ' | waitingQueries='.$sth_to_test->rows.';'.$warning.';'.$critical if ($perfdata_value);
		print "\n";
	}
	else {
		if ($sth_to_test->rows > 0) {
			print $display.' OK - success to access to '.$postgres_login.'@'.$postgres_host.':'.$postgres_port.' on database '.$postgres_dbname;
			print " | postgresUp=1" if ($perfdata_value);
			print "\n";
		}
		else {
			$status = 'CRITICAL';
			print $display.' CRITICAL - problem with the "SELECT 1" request which returns nothing';
			print " | postgresUp=0" if ($perfdata_value);
			print "\n";
		}
	}
	$sth_to_test->finish();
}
else {
	$status = 'CRITICAL';
	print $display.' UNKNOWN - impossible to connect on '.$postgres_login.'@'.$postgres_host.':'.$postgres_port.' on database '.$postgres_dbname."\n";
}

$dbh_to_test->disconnect();

exit $ERRORS{$status};


# ####################################################################
# function 1 :  display the help
# ------------------------------
sub print_usage() {
    print <<EOT;
$script_name version $version by $author

A simple perl script to test if a PostgreSQL instance is up or not + to monitore the number of
waiting queries

Usage: /<path-to>/$script_name -H 127.0.0.1 -P 5432 -U nagios -W password -B template1 [-v] [-p] [--type isAlive] [-c 5] [-w 2] [-D "CHECK PostgreSQL -"]

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -H, --host=STRING
    Specify the PostgreSQL host
    default is 127.0.0.1
 -P, --port=INTEGER
    Specify the PostgreSQL port
    default is 5432
 -U, --user=STRING
    Specify the PostgreSQL username
    default is nagios
 -W, --password=STRING
    Specify the PostgreSQL password
    default is password
 -B, --database=STRING
    Specify the database to connect to
    default is template1
 -t, --type=[waintingQueries|isAlive]
    Specify the type of check
	* isAlive: check if the PostgreSQL instance is up
	* waintingQueries: check the amount of waiting queries
    default is isAlive
 -c, --critical=INT
    Specify a critical threshold for the number of waiting queries
    default is 5
    only used for the waintingQueries
 -w, --warning=INT
    Specify a warning threshold for the number of waiting queries
    default is 2
    only used for the waintingQueries
 -p, --perfdata
    If you want to activate the perfdata output
 -D, --display=STRING
    To modify the output display... 
    default is "CHECK PostgreSQL -"
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
