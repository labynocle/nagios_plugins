#!/usr/bin/perl -w

#  -------------------------------------------------------
#             -=- <check_jmeter-scenario.pl> -=-
#  -------------------------------------------------------
#
#  Description : this plugin is able to check a JMX plan.
#  You're now able to use a scenario to check your web
#  server.
#
#  This plugin is inspired by the work of Travis Noll
#  (http://yoolink.to/eG3)
#
#  Version : 0.2
#  -------------------------------------------------------
#  In :
#     - see the How to use section
#
#  Out :
#     - print on the standard output 
#     - create a temporary file (if the result is NON-OK the temporary
#	is kept) , specify the path thanks to the -l,--log parameter)
#
#  Features :
#     - perfdata output
#
#  Fix Me/Todo :
#     - too many things ;) but let me know what do you think about it
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
#	1 - Download the jmeter binary here : 
#			http://jakarta.apache.org/site/downloads/
#
#	2 - Display the help to see how use this plugin
#
# ####################################################################

# ####################################################################
# Changelog :
# -----------
#
# --------------------------------------------------------------------
#   Date:22/01/2013   Version:0.2     Author:Erwan Ben Souiden
#   >> use XML::LibXML to parse the result file
#   perfdata now include the time to process the plan
# --------------------------------------------------------------------
#   Date:13/11/2010   Version:0.1     Author:Erwan Ben Souiden
#   >> creation
# ####################################################################

# ####################################################################
#            Don't touch anything under this line!
#        You shall not pass - Gandalf is watching you
# ####################################################################

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
#use Date::Manip;
use XML::LibXML;
use IPC::Open3;

# Generic variables
# -----------------
my $version = '0.2';
my $author = 'Erwan Labynocle Ben Souiden';
my $a_mail = 'erwan@aleikoum.net';
my $script_name = 'check_jmeter-scenario.pl';
my $verbose_value = 0;
my $version_value = 0;
my $more_value = 0;
my $help_value = 0;
my $perfdata_value = 0;
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# Plugin default variables
# ------------------------
my $display = 'CHECK_JMETER-SCENARIO - ';
my ($critical,$warning,$timeout) = (2,1,30);
my ($jmeter_directory,$plan,$log) = ('','','');

Getopt::Long::Configure("no_ignore_case");
my $getoptret = GetOptions(
			'j|jmeter_dir=s'	=> \$jmeter_directory,
			'pl|plan=s'		=> \$plan,
			'l|log=s'		=> \$log,
			't|timeout=i'		=> \$timeout,
			'c|critical=i'		=> \$critical,
			'w|warning=i'		=> \$warning,
			'V|version' 		=> \$version_value,
			'h|H|help' 		=> \$help_value,
    			'D|display=s' 		=> \$display,
    			'p|perfdata' 		=> \$perfdata_value,
    			'v|verbose' 		=> \$verbose_value
);

print_usage() if ($help_value);
print_verson() if ($version_value);

# Syntax check of your specified options
# --------------------------------------

print 'DEBUG: jmeter_directory: '.$jmeter_directory.' plan:'.$plan.' log: '.$log."\n" if ($verbose_value);

if (($jmeter_directory eq "") or ($plan eq "") or ($log eq "")) {
    print $display.'one or more following arguments are missing :jmeter_directory/plan/log'."\n";
    exit $ERRORS{"UNKNOWN"};
}

if (! -e "$jmeter_directory/bin/ApacheJMeter.jar") {
    print $display.'unable to find '.$jmeter_directory.'/bin/ApacheJMeter.jar'."\n";
    exit $ERRORS{"UNKNOWN"};
}

if (! -e "$jmeter_directory/bin/jmeter.properties") {
    print $display.'unable to find '.$jmeter_directory.'/bin/jmeter.properties'."\n";
    exit $ERRORS{"UNKNOWN"};
}

if (! -e $plan) {
    print $display.'unable to find '.$plan."\n";
    exit $ERRORS{"UNKNOWN"};
}

# Core script
# -----------

my $command_jmeter = 'java -server -jar '.$jmeter_directory.'/bin/ApacheJMeter.jar --nongui --propfile '.$jmeter_directory.'/bin/jmeter.properties --testfile '.$plan.' --logfile '.$log;
my $return = 'scenario validated';
my $plugstate = 'OK';

print 'DEBUG: jmeter command: '.$command_jmeter."\n" if ($verbose_value);

local (*HIS_IN, *HIS_OUT, *HIS_ERR);

# Invoke the java/jmeter process.
my $childpid = open3(*HIS_IN, *HIS_OUT, *HIS_ERR, $command_jmeter);

# We will only run for so long.  Handle an alarm signal as a reason to kill the
# spawned child process and exit.
$SIG{'ALRM'} = sub {
	$plugstate = 'CRITICAL';
	print $display.$plugstate.' - timeout '.$timeout.' expired'."\n";
	if ($childpid) {
		kill 1, $childpid;
	}
	exit $ERRORS{$plugstate};
};
alarm($timeout);

close HIS_IN;  ### sends eof to child
my @errs = <HIS_ERR>;
close HIS_OUT;
close HIS_ERR;

# When we close HIS_ERR $? becomes the status.
if ($? || @errs) {
	$plugstate = 'CRITICAL';
	print $display.$plugstate.' - jmeter command exit with wait status of '.$?.'with the following error '.join("\n",@errs);
	exit $ERRORS{$plugstate};
}

my $parser = XML::LibXML->new();
my ($start_time,$end_time) = (0,0);
my ($failure_count,$error_count) = (0,0);
my ($current_time,$current_test) = ('','');
my $xmldoc = $parser->parse_file($log);
for my $sample ($xmldoc->findnodes('testResults/httpSample')) {

	$current_time = $sample->getAttribute("ts");
	$current_test = $sample->getAttribute("tn");

	print 'DEBUG : analyzing test: '.$current_test.' - the test started at:'.$current_time."\n" if ($verbose_value);
	    
	if (! $start_time) {
		$start_time = $current_time;
	}
	else {
		$end_time = $current_time;
	}
    
	for my $property ($sample->findnodes('./assertionResult/*')) {
		if (($property->nodeName() eq 'failure') and ($property->textContent() eq 'true')) {
			print 'DEBUG : failure detected during the following test: '.$current_test."\n" if ($verbose_value);
			$failure_count++;
		}
		elsif (($property->nodeName() eq 'error') and ($property->textContent() eq 'true')) {
			print 'DEBUG : error detected during the following test: '.$current_test."\n" if ($verbose_value);
			$error_count++;
		}
		else {
			# do nothing
		}
	}
}

my $time_spent = $end_time - $start_time;
my $total_problem = int($error_count) + int($failure_count);

print 'DEBUG : critical threshold: '.$critical.', warning threshold: '.$warning."\n" if ($verbose_value);
print 'DEBUG : error_count: '.$error_count.', failure_count: '.$failure_count.' total problem: '.$total_problem."\n" if ($verbose_value);
print 'DEBUG : test done in: '.$time_spent.'ms, start time: '.$start_time.', stop time: '.$end_time."\n" if ($verbose_value);
$plugstate = 'WARNING' if ($total_problem >= $warning);
$plugstate = 'CRITICAL' if ($total_problem >= $critical);

if ($plugstate eq "OK") {
	unlink ($log);
}
else {
	my $log_keep = $log.int(rand(10000));
	#`mv $log $log_keep`;
    rename "$log", "$log_keep";
    print 'DEBUG : state is No-OK, keep the log '.$log.' as '.$log_keep."\n" if ($verbose_value); 
	$return = 'scenario not validated - error_count: '."$error_count".' / failure_count: '."$failure_count".' please check '.$log_keep.' for debug';
}
$return .= ' | timeSpent='.$time_spent.'ms' if ($perfdata_value);
print $display.$plugstate.' - '.$return."\n";
exit $ERRORS{$plugstate};


# ####################################################################
# function 1 :  display the help
# ------------------------------
sub print_usage {
    print <<EOT;
$script_name version $version by $author

Don't forget to download the jmeter : http://jakarta.apache.org/site/downloads/

Usage : /<path-to>/$script_name -j /<path-to>/jakarta-jmeter-2.4/ -pl /<path-to>/scenario.jmx -l /<path-to>/log [-p] [-D "$display"] [-v] [-c 2] [-w 1]

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -D, --display=STRING
    To modify the output display... 
    default is "CHECK_JMETER-SCENARIO - "
 -p, --perfdata
    If you want to activate the perfdata output (display the time to process the plan - in ms)
 -v, --verbose
    Show details for command-line debugging (Nagios may truncate the output)
 -c, --critical=INT
    Specify a critical threshold of tolerated errors in the log
    default is 2
 -w, --warning=INT
    Specify a critical threshold of tolerated errors in the log
    default is 1
 -j, --jmeter_dir=STRING
    Specify the path to the jmeter directory
 -t, --timeout=INT
    Specify the jmeter execution timeout.
    If the jmeter execution exceeds this value, the execution is stopped
    and the plugin returns an UNKNOWN state.
    default is 30
 -l, --log=STRING
    Specify the path to the log which will be generated by jmeter
    If the plugin returns a NON-OK state the log is kept with a new name.
 -pl, --plan=STRING
    Specify the path to the plan (the jmx scenario)
  
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
sub print_version {
    print <<EOT;
$script_name version $version
EOT
    exit $ERRORS{"UNKNOWN"};
}
