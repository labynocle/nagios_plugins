#!/usr/bin/perl

#  -------------------------------------------------------
#                  -=- <check_coraid.pl> -=-
#  -------------------------------------------------------
#
#  Description : an alternative way to check your Coraid
#  		 Device for Nagios
#
#  Version : 0.1.4
#  -------------------------------------------------------
#  In :
#     - see the How to use section 
#
#  Out :
#     - a file will be generated for each couple action/interface
#	you will check
#
#  Features :
#     - perfdata output
#     - choose which lblade to poll for the raid action (NOT YET)
#
#  Fix Me :
#     - too many things ;) but let me know what do you think about it
#  
#  Special thanks :
#     - This script is inspired on 'cec-chk-coraid.sh' by William A. Arlofski 
#	(http://www.revpol.com/coraid_scripts).
#     - To Randall Whitman who sends me patch & feedbacks <http://whizman.com>
#
# ####################################################################

# ####################################################################
# This file is part of Nagios Check Coraid.
#
# Nagios Check Coraid is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Nagios Check Coraid is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Nagios Check Coraid.  If not, see <http://www.gnu.org/licenses/>.
# ####################################################################

# ####################################################################
# How to use :
# ------------
#
# First you have to edit the following variables of check_coraid.pl
# (Path variables) and adapt it to your configuration :
#        statedir : path to save expect scripts outputs
#        cec : path to cec program
#        expect : path to expect program
#        expect_script : path to expect_scripts folder
#
# Add the following entry to your sudoers file to have the good privileges
# to run the check_coraid.pl script :
#        nagios ALL=(ALL) NOPASSWD: /<path-to>/check_coraid.pl
#
# Then just run this command line to display help :
#        $ sudo /<path-to>/check_coraid.pl -h


# /!\ may be you have to adapt the except script to your config /!\
# -----------------------------------------------------------------
#	- may be you have to change the cec prompt start (depends of
#	  your coraid firmware
#	- in the same way the escape character could be different but
#	  according to the cec man page with the -e option you can 
#	  specify which character you will use to exit the cec
#	  command line interface... be aware !
#	  

# ####################################################################

# ####################################################################
# Changelog :
# -----------
#
# --------------------------------------------------------------------
#   Date:11/06/2011   Version:0.1.4     Author:Randall Whitman
#   >> improvements
#	- elsif for conditionals understood to be mutually exclusive
#	- "SRX shelf" is the start of the prompt we see in cec
#	- spell "lblade" consistently
#	- warn level threshold for spare
# --------------------------------------------------------------------
#   Date:07/08/2010   Version:0.1.3     Author:Erwan Ben Souiden
#   >> little improvement
#      several option checks, add a new action for new feature,
#      change the way you die when you fail to open a "statefile"
# --------------------------------------------------------------------
#   Date:12/06/2009   Version:0.1.2     Author:Erwan Ben Souiden
#   >> update of all regexp
#      now the shelf number is an argument for expect script
#      forgot missing state for the show action
# --------------------------------------------------------------------
#   Date:29/04/2009   Version:0.1.1     Author:Erwan Ben Souiden
#   >> spare regexp update
# --------------------------------------------------------------------
#   Date:14/04/2009   Version:0.1     Author:Erwan Ben Souiden
#   >> creation
# ####################################################################

use strict;
use Getopt::Long qw(:config no_ignore_case);


# Path variables
# --------------
my $statedir = '/tmp/check_coraid/';
my $cec = '/usr/sbin/cec';
my $expect = '/usr/bin/expect';
my $expect_scripts = '/usr/local/NagiosCheckCoraid/expect_scripts/';

# ####################################################################
#  		     Don't touch anything under this line!
#	     You shall not pass - Gandalf is watching you
# ####################################################################

# Generic variables
# -----------------
my $version = '0.1.3';
my $author = 'Erwan Labynocle Ben Souiden';
my $a_mail = 'erwan@aleikoum.net';
my $script_name = 'check_coraid.pl';
my $verbose_value = 0;
my $version_value = 0;
my $more_value = 0;
my $help_value = 0;
my $perfdata_value = 0;
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# Plugin default variables
# ------------------------
my $interface = 'eth0';
my $shelf = 0;
my $display = 'CHECK CORAID - ';
my $action = 'show';
my $warn = 0;
my $critical = 0;
my $firmware = 0;

GetOptions (
	'i=s' => \ $interface,
	'interface=s' => \ $interface,
	'a=s' => \ $action,
	'action=s' => \ $action,
	's=i' => \ $shelf,
	'shelf=i' => \ $shelf,
	'w=i' => \ $warn,
	'warn=i' => \ $warn,
	'c=i' => \ $critical,
	'critical=i' => \ $critical,
	'f' => \ $firmware,
	'firmware' => \ $firmware,
	'V' => \ $version_value,
	'version' => \ $version_value,
	'h' => \ $help_value,
	'H' => \ $help_value,
	'help' => \ $help_value,
	'm' => \ $more_value,
	'more' => \ $more_value,
	'display=s' => \ $display,
	'D=s' => \ $display,
	'perfdata' => \ $perfdata_value,
	'p' => \ $perfdata_value,
	'v' => \ $verbose_value,
	'verbose' => \ $verbose_value
);

print_usage() if ($help_value);
print_version() if ($version_value);

# Syntax check of your specified options
# --------------------------------------

# With the new firmware show action is deprecated
# Now we have to use the disks action
if (($action eq 'show') & ($firmware > 0)) {
	$action='disks';
}
if (($shelf < 0) & ($shelf >= 99)) {
	print "DEBUG : shelf = $shelf\n" if ($verbose_value);
	print $display.'problem ! shelf value must be between 0 and 99'."\n";
        exit $ERRORS{"UNKNOWN"};
}

if ((! -x $cec) || (! -x $expect) || (! -x $expect_scripts."expect-".$action.".sh")) {
	print "DEBUG : cec = $cec,expect=$expect,expect-script=$expect_scripts"."expect-$action.sh\n" if ($verbose_value);
	#print $display."$cec".' and '."$expect".' must be executable'."\n";
        #exit $ERRORS{"UNKNOWN"};
}

if (! -d $statedir) {
	print "DEBUG : $statedir doesn't exist, we have to create it\n" if ($verbose_value);
	mkdir ("$statedir") or (print $display.'problem when creating '."$statedir"."\n" and exit $ERRORS{"UNKNOWN"});
}

if ($critical < 0) {
	print "DEBUG : critical = $critical\n" if ($verbose_value);
	print $display.'problem ! critical value must be greater than 0'."\n";
        exit $ERRORS{"UNKNOWN"};
}

# Core script
# -----------

my $statefile = $statedir.$interface."_".$shelf."-$action";
my $commande = $expect_scripts."expect-$action.sh $interface $statefile $cec $expect $shelf";
my $retour = "";
my $plugstate = "OK";
#my $descfile= uc ("$action".'FILE');

print "DEBUG : commande : $commande\n" if ($verbose_value);

# show and disks action
# ---------------------
if ($action eq 'show') {
	`$commande`;

	#  shelf 0> show -l
   	#	0.0  1000.205GB up
   	#	0.1  1000.205GB up
   	#	0.2  1000.205GB up
   	#	0.3     0.000GB down
   	#	0.4     0.000GB down
   	#	0.5     0.000GB down
   	#	0.6     0.000GB down
   	#	0.7     0.000GB down
   	#	0.8     0.000GB down
   	#	0.9     0.000GB down
   	# 	0.10    0.000GB down
   	# 	0.11    0.000GB down
   	# 	0.12    0.000GB down
	# 	0.13    0.000GB down
	# 	0.14 1000.205GB up
	#  shelf 0> 

	my $compteur = 0;
	open my $descfile,$statefile or (print $display.'problem when trying to open '."$statefile"."\n" and exit $ERRORS{"UNKNOWN"});
	while (<$descfile>) {
		chomp($_);
		if ($_=~/^\s*?(\S+)\s+(\S+GB)\s+(\S+)/){
			print "DEBUG : id_disk $1 / size $2 / state $3\n" if ($verbose_value);
			if (($3 ne 'down') && ($3 ne 'missing')){
				$retour .= "($1,$2) ";
				$compteur++;
			}
		}
	}
	close($descfile);
	$retour .= "are detected as UP";
	$retour = "no disk found as UP" if (! $retour);
	$retour .= " - $compteur disks UP" if ($more_value);
	$retour .= " | nbdisksUP=$compteur" if ($perfdata_value);

	print "DEBUG : compteur : $compteur et critical : $critical \n" if ($verbose_value);
	$plugstate = "CRITICAL" if (($compteur < $critical) || ($compteur == 0));
}

elsif ($action eq 'disks') {
	`$commande`;

	#  shelf 2> disks
	#DISK             SIZE                      MODEL  FIRMWARE              MODE
	#2.0        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.1        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.2        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.3        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.4        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.5        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.6        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.7        2000.398GB    Hitachi HUA722020ALA330  JKAOA3EA     sata 3.0 Gb/s
	#2.8           missing 
	#2.9           missing 
	#2.10          missing 
	#2.11          missing 
	#2.12          missing 
	#2.13          missing 
	#2.14          missing 
	#2.15          missing
	#  shelf 2> 

	my $compteur = 0;
	open my $descfile,$statefile or (print $display.'problem when trying to open '."$statefile"."\n" and exit $ERRORS{"UNKNOWN"});
	while (<$descfile>) {
		chomp($_);
		if ($_=~/^($shelf\S+)\s+(\S+)/){
			print "DEBUG : id_disk $1 / size $2\n" if ($verbose_value);
			if (($2 ne 'down') && ($2 ne 'missing')){
				$retour .= "($1,$2) ";
				$compteur++;
			}
		}
	}
	close($descfile);
	$retour .= "are detected as UP";
	$retour = "no disk found as UP" if (! $retour);
	$retour .= " - $compteur disks UP" if ($more_value);
	$retour .= " | nbdisksUP=$compteur" if ($perfdata_value);

	print "DEBUG : compteur : $compteur et critical : $critical \n" if ($verbose_value);
	$plugstate = "CRITICAL" if (($compteur < $critical) || ($compteur == 0));
}

# raid action
# -----------
elsif ($action eq 'raid') {
	`$commande`;
	
	#  shelf 0> list -l
 	#   0 2000.410GB online
  	#     0.0   2000.410GB raid5 
    	#	0.0.0  normal     1000.205GB 0.0
    	#	0.0.1  normal     1000.205GB 0.1
    	#	0.0.2  normal     1000.205GB 0.14
	#  shelf 0> 

	my $detrompeur = 0;
	open my $descfile,$statefile or (print $display.'problem when trying to open '."$statefile"."\n" and exit $ERRORS{"UNKNOWN"});
        while (<$descfile>) {
                chomp($_);
                if ($_=~/^\s*?(\S+)\s+(\S+GB)\s+(offline|online)/) {
			
                        print "DEBUG : lblade $1 / size $2 / state $3\n" if ($verbose_value);
			$retour .= " and " if ($detrompeur);	
			$retour .= "lblade $1 ($2,$3,";
			$detrompeur = 1;

			$plugstate = "WARNING" if ($4=~/offline/);
                }
		elsif ($_=~/^\s*?(\S+)\s+(\S+GB)\s+(raid\S+|update)\s+(.*)/) {
                        print "DEBUG : idraid $1 / size $2 / $3 / $4\n" if ($verbose_value);
                        $retour .= "$3) ";
			$retour .= " composed by " if ($more_value);
			
			# state : initing | recovering | degraded | failed | normal
			$plugstate = "CRITICAL" if ($4=~/failed|degraded/);
			$plugstate = "WARNING" if (($4=~/initing|recovering/) && ($plugstate ne 'CRITICAL'));
                }
		elsif ($_=~/^\s*?(\S+)\s+(\S+)\s+(\S+GB)\s+(\S+)/) {
                        print "DEBUG : idraiddisk $1 / state $2 / size $3 / iddisk $4\n" if ($verbose_value);
                        $retour .= "($4,$3,$2) " if ($more_value);

			# state : failed | missing | replaced | normal
			$plugstate = "CRITICAL" if ($2=~/failed|missing/);
			$plugstate = "WARNING" if (($4=~/replaced/) && ($plugstate ne 'CRITICAL'));
                }
        }
        close($descfile);
}

# spare action
# ------------
elsif ($action eq 'spare') {
	`$commande`;

	#  shelf 0> spare 
	# 0.10	1000.205GB
	# 0.11	1000.205GB
	#  shelf 0> 

	my $compteur = 0;
	open my $descfile,$statefile or (print $display.'problem when trying to open '."$statefile"."\n" and exit $ERRORS{"UNKNOWN"});
        while (<$descfile>) {
                chomp($_);
                if ($_=~/^\s*?(\S+)\s+(\S+GB)/){
                        print "DEBUG : id_disk $1 / size $2 \n" if ($verbose_value);
                        $retour .= "($1,$2) ";
			$compteur++;
                }
        }
        close($descfile);
	if ($retour) {
        	$retour .= "detected as SPARE";
	}
	else {
		$retour = "no disk found as SPARE";
	}
	$retour .= " - $compteur disk(s) as SPARE" if ($more_value);
	$retour .= " | nbdisksSPARE=$compteur" if ($perfdata_value);

	if (($compteur < $critical) || ($compteur == 0)) {
	    $plugstate = "CRITICAL";
	} elsif ($compteur < ($warn || 0)) {
	    $plugstate = "WARNING";
	}
}

# when action
# -----------
elsif ($action eq 'when') {
        `$commande`;

	# lines :
        #  shelf 0> when
        # 0.10 90701  KBps  0:55:18 left
        #  shelf 0> >>>

	my $compteur = 0;
	open my $descfile,$statefile or (print $display.'problem when trying to open '."$statefile"."\n" and exit $ERRORS{"UNKNOWN"});
	while (<$descfile>) {
        	chomp($_);
	        if ($_=~/^\s*?(\S+)\s+\d+\s+KBps\s+(\d+:\d+:\d+)\s+left/){
        		print "DEBUG : id_disk $1 / time_left $2 \n" if ($verbose_value);
			$retour .= "($1,$2) ";
			$compteur++;
		}
	}
	close($descfile);

	$retour = 'no disk in initing or recovering state' if (! $retour);
	$retour .= " - $compteur disk(s) in initing or recovering state" if ($more_value);
	$retour .= " | nbdisksRECO=$compteur" if ($perfdata_value);

	$plugstate = "WARNING" if ($compteur > 0);
}

else {
	print "DEBUG : action = $action\n" if ($verbose_value);
        print $display.'problem ! action value must be "show" or "spare" or "raid" or "when"';
        exit $ERRORS{"UNKNOWN"};
}

print $display.$action." - ".$plugstate." - ".$retour;
exit $ERRORS{$plugstate};

# ####################################################################
# function 1 :  display the help
# ------------------------------
sub print_usage() {
	print <<EOT;
$script_name version $version by $author

This plugin checks

Usage: /<path-to>/$script_name [-s 0] [-a show] [-i eth0] [-v] [-m] [-c 0] [-p] [-D "CHECK CORAID - "]

Options:
 -h, --help
	Print detailed help screen
 -V, --version
	Print version information
 -s, --shelf=STRING
	specify the shelf number
	default is 0
 -f, --firmware
	use this option if your firmware is greater than ???????	
 -a, --action=STRING
	specify the action : show|disks|raid|spare|when
	default is show
    show : display the number of "UP" disks use the -c argument to specify
           a threshold
    disks : exactly the same as the show action. Show action is deprecated
            with new firmware
    spare : display the number of "SPARE" disks disks use the -c argument to 
            specify a threshold
    when : display the number of disks in a initing or recovering state.
           a warning alarm will be generated if there is one or more disks 
           detected
    raid : display every lblades and their informations (size, raid type)
           a warning alarm will be generated if 
                            the lblade is offline
                            the raid is in a initing or recovering state
                            lblade disks are in a replaced state
           a critical alarm will be generated if
                            the raid is in a failed or degraded state
                            lblade disks are in a failed or missing state
 -i, --interface=STRING
	specify the interface which communicates with the CORAID
	default is eth0
 -c, --critical=INT
	specify a threshold for the show and spare action.
	default is 0
 -m, --more
	Print a longer output. By default, the output is not complet because
	Nagios may truncate it. This option is just for you
 -p, --perfdata
	If you want to activate the perfdata output
 -D, --display=STRING
	to modify the output display... 
	default is "CHECK CORAID - "
 -v, --verbose
	Show details for command-line debugging (Nagios may truncate the output)
	
Send email to $a_mail if you have questions
regarding use of this software. To submit patches or suggest improvements,
send email to $a_mail
This plugin has been created by $author

Hope you will enjoy it ;)

Remember :
This file is part of Nagios Check Coraid.

    Nagios Check Coraid is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Nagios Check Coraid is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Nagios Check Coraid.  If not, see <http://www.gnu.org/licenses/>.
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
