# backupCiscoConfigs.pl

# Created by: 	Gregg Hinrichs
# Version:	1.0.0
# Last Update:	4/15/11
#

# This program will do an snmp set to all Cisco switches which will backup a copy of its config to
# a TFTP server

#
# use strict;

#### Start backupCiscoConfigs.pl

# Open file to read from
open($fi, '<', 'Switches.txt')  || die "Cannot open file: $!"; # Cannot open switches.txt

# Open a log file
open(logFile, '>ciscoBackup.log') || die "Cannot open file: !"; # Cannot open file 

# Declare variables
$iAddress = 0; # Ip address read from file
$iResults = 0; # Return status of the system command
$iResults1 = 0; # Return results of the second system command
$iSysName = ""; # Return the system name

# Process the switches file while TRUE
while ( <$fi> )  {
	chomp $_;
	$iAddress = $_;
	print "$iAddress \n";
	print "$iSysName \n";
	# $iSysName = system ("\"f:\\Program Files (x86)\\HP\\HP BTO Software\\bin\\nnmsnmpget.ovpl\" -u ghinrichs -p baxter -c BlueBird59 $iAddress .1.3.6.1.2.1.1.5.0);
	$iResults = system ("\"f:\\Program Files (x86)\\HP\\HP BTO Software\\bin\\nnmsnmpset.ovpl\" -u ghinrichs -p baxter -v 1 -c RedRaven94 $iAddress .1.3.6.1.4.1.9.2.1.55.172.17.2.157 octetstring $iAddress.text");
	print "$iResults \n";
	#print "$iSysName \n";
	next;
} # end While - file process loop
close logFile;
#### end of backupCiscoConfigs.pl

