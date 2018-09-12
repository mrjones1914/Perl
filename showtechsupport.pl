#!/usr/bin/perl 
#
# File: $Id: //depot/main/rs_92/usr.src/netscaler/scripts/showtechsupport.pl#16 $
# Last checkin:   $Author: appajik $
# Date of last submission: $Date: 2010/11/09 $
# Revision number: $Revision: #16 $
# Changelist number: $Change: 226899 $

use strict; 
use File::Path;
use File::Copy;
use Sys::Syslog;

#########################################################################
# Some global configurable variables. For now, they are set here, but in
# the future, we can make these as arguments passed as command line options
#########################################################################

my $NUM_FILES_TO_COLLECT = 5; #Number of files to be collected from a dir
my $MAX_FILESIZE_TOTAL = 1.5 * 1024 * 1024 * 1024; #1.5GB
my $NUM_PREV_DAYS_FILES = 7; #Number of days from which to look for files

######################################################################
# Other global variables (internally used - NOT TO BE MODIFIED!
######################################################################

my $support_dir = "/var/tmp/support"; #This may be changed later
my $hd_support_dir = "/var/tmp/support"; #This is the one created on hard disk
my $collector_base_dir = "";	#This will be set later
my $collector_abs_path = "";	#This will be set later
my $ns_version = ""; #This will be set later
my $hd_device = ""; #This will be set later
my $flash_device = ""; #This will be set later

# syslog related variables for logging
my $syslog_ident    = "showtechsupport.pl: ";
my $syslog_opt      = "ndelay,pid,nofatal,perror";
my $syslog_facility = "LOG_USER";
my $syslog_level    = "LOG_NOTICE";

##################################################################
# MAIN ENTRY POINT. Call main() that does the whole thing.
##################################################################

&main(); 

#####################################################################
# Main function that collects data step by step through separate functions
######################################################################

sub main()
{
	# Open syslog facility for logging anything.
	openlog $syslog_ident, $syslog_opt, $syslog_facility;

	my $p4_rev_string = '$Revision: #16 $';
	&log_debug_message("\nshowtechsupport data collector tool - $p4_rev_string!\n");

	# Get the NetScaler version and hard disk
	&get_ns_version();
	&get_hard_disk_device();

	# Prepare directory structure for the tool to collect data
	&prepare_support_dir(); 

	# Copy all config files
	&copy_nsconfig_dir(); 

	# Run BSD shell commands 
	&exec_shell_cmds(); 

	# Run NetScaler CLI show commands
	&exec_show_cmds();

	# Run NetScaler CLI stat commands
	&exec_stat_cmds(); 

	# Run NetScaler vtysh commands
	&exec_vtysh_cmds();

	# Copy newnslog files
	&copy_newnslog_files(); 

	# Copy application core files
	&copy_core_files("/var/core","$collector_abs_path/var/core","*");

	# Copy kernel mini core files
	&copy_core_files("/var/crash","$collector_abs_path/var/crash","nsminicore.*");

	# Copy all log files (ns.log*, messages*, dmesg.*)
	&copy_log_files(); 

	# Finally, create a tar archive of the collector directory that 
	# we populated.
	&prepare_tar_archive();
	&log_debug_message("If this node is part of HA pair, please run it on the other node also!!\n\n");

	# Close syslog facility
	closelog;
}

#########################################################################
# This routine creates the directory structure necessary to collect the files.
# /var/tmp/support is the base directory and beneath it is where all files will be 
# collected.
#################################################################################

sub prepare_support_dir()
{
	# Because of the 'use strict pragma' we need to define the variables here
	# Variables declared with "my" are accessed faster than ordinary variables.
	my @months;
	my $dummy;
	my $min;
	my $hour;
	my $mon;
	my $year;
	my $mday;

	# The directory that we eventually create is of the form "collector_<IP>_<Date>_<Time>"
	# All the directories of this type will be under $support_dir

	# Check if the support dir exists and create if it does not. This is true for both if hard drive is present
	# and the case of hard drive not mounted
	if (!-d $support_dir) {
		&log_debug_message("Creating $support_dir ....\n");
		mkpath("$support_dir") || die "Unable to create $support_dir!\n\n";
	}

	# If hard disk is not mounted, the support directory will be in /flash/support, instead of
	# /var/tmp/support
	if ($hd_device eq "") {
		$support_dir = "/flash/support";
		if (!-d $support_dir) {
			&log_debug_message("Creating $support_dir ....\n");
			mkpath("$support_dir") || die "Unable to create $support_dir!\n\n";
		}
	}

	chdir $support_dir;

	# Create a base directory of the form "collector_<IP>_<Date>_<Time>"
	my $nsip;
	if (($nsip = get_nsip_address()) == "") {
		die "Could not get the NS IP address or HA state of this box. Exiting!!\n\n";
	}
	$collector_base_dir = "collector_" . $nsip;
	
	chomp($collector_base_dir);

	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

	# The fields that we get using localtime are the following:
	#     ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)

	($dummy,$min,$hour,$mday,$mon,$year,$dummy,$dummy,$dummy) = localtime(time);
	$year += 1900;
	# If the hour and minutes are in single digits, prefix with a "0"
	if ($hour < 10) {
		$hour = "0". $hour;
	}
	if ($min < 10) {
		$min = "0". $min;
	}
	$collector_base_dir = 
		$collector_base_dir . $mday . $months[$mon] . $year . "_" . $hour . "_" . $min;

	if (-d $collector_base_dir) {
		# If the directory exists, this tool was run in the last minute.
		# Remove the existing directory and create again.
		&log_debug_message("This tool was just run in the last one minute!\n");
		&log_debug_message("The data in this directory will be overwritten!\n");
		rmtree("$collector_base_dir",0,1) || &log_debug_message("Unable to remove $collector_base_dir\n");
	}

	&log_debug_message("All the data will be collected under \n\t$support_dir/$collector_base_dir\n");
	mkdir("$collector_base_dir") || die "Unable to create $collector_base_dir!!\n\n";

	# Create additional directories below the top level
	my @sub_dirs = ("var", "shell", "nsconfig", "var/core", "var/log", "var/nslog", "var/crash", "etc", "var/nssynclog", "var/nsproflog");
	foreach my $dir (@sub_dirs) {
		mkdir("$collector_base_dir/$dir") ||
			die "Unable to create $collector_base_dir/$dir!!\n\n";
	}
	$collector_abs_path = $support_dir . "/" . $collector_base_dir;
}

#########################################################################
# This routine gets the NS IP address of the box.
#################################################################################

sub get_nsip_address()
{
	my $line;
	my $ip = "";
	my $state;
	my $dummy;
	my $ha_state = "";

	my @show_node_output = `nscli -U %%:.:. show node 2>&1`;
	foreach $line (@show_node_output) {
		$_ = $line;
		if (/IP:/) {
			chomp($_);
			($ip) = (split /IP:/)[1];	#Use : as the delimiter
			$ip =~ s/^\s+//;		#Remove trailing whitespaces
			$ip =~ s/\s+\(.+\)//;	#Remove in between whitespaces and the (<hostname>) string
			$ip =~ s/\s+$//;		#Remove ending whitespaces
			&log_debug_message("The NS IP of this box is $ip\n");
		}
		if (/Master State:/) {
			# Output here is of the form   "Master State: Primary"
			($dummy,$state) = split(/:/);   #Use : as the delimiter
			if ($state =~ "Primary") {
				$ha_state = "P_";
				&log_debug_message("Current HA state: Primary (or this is not part of HA pair!)\n");
			}
			else {
				if ($state =~ "Secondary") {
					$ha_state = "S_";
					&log_debug_message("Current HA state: Secondary\n");
				}
			}
			# NOTE: We are returning here with the assumption that this line
			# in show node output appears after the IP address line
			return ($ip."_".$ha_state);
		}
	}
	# It shouldn't come here, as the "Master State:" line should be found above
	return ($ip."_".$ha_state);
}

#########################################################################
# Copy the nsconfig directory that has all the configuration files
#########################################################################

sub copy_nsconfig_dir()
{
	# Copy only selected files from /nsconfig directory
	&log_debug_message("Copying selected configuration files from nsconfig ....\n");
	
	# Copy all files first, but do clean up of passwords next
	chdir "/flash/nsconfig";
	`cp -p * $collector_abs_path/nsconfig 2>/dev/null`;
	`cp -R -p monitors $collector_abs_path/nsconfig 2>/dev/null`;
	`cp -p /flash/boot/loader.conf* $collector_abs_path/nsconfig 2>/dev/null`;

	# Clean up by removing passwords from ns.conf* files
	my @filelist = glob("ns.conf*");
	foreach my $file (@filelist)
	{
		`egrep -v "set system user nsroot|add system user|set ns rpcNode" $file > $support_dir/$file.$$`;
		`mv $support_dir/$file.$$ $collector_abs_path/nsconfig/$file`;
	}
}

#########################################################################
# Copy the messages.*, ns.log* and dmesg* files
#########################################################################

sub copy_log_files()
{
	# Define the sets of files to be copied here. 
	# First column is the set of files to be copied
	# Second column is the destination folder under $collector_abs_path

	# Handle directory that includes files that are pipes, eg. NSPPE-0.log.
	# We can't copy those because the copy will never complete.
	if ($hd_device ne "") {
		`find /var/nslog/ -name "*.log" -type f | xargs -n 1 -I {} cp -p {} $collector_abs_path/var/nslog 2>/dev/null`;
	}

	my %files_to_be_copied = (
		# Files under /var/log
		"/var/log/messages*",		"var/log",
		"/var/log/*.log",		"var/log",
		"/var/log/ns.log.*",		"var/log",
		"/var/log/httpaccess.log.*",	"var/log",
		"/var/log/httperror.log.*",	"var/log",
		"/var/log/auth.log.*",		"var/log",
		"/var/log/wicmd.log.*",		"var/log",

		# Files under /var/nslog
		"/var/nslog/nslog.nextfile",	"var/nslog",
		"/var/nslog/dmesg.boot",	"var/nslog",
		"/var/nslog/dmesg.prev",	"var/nslog",
		"/var/nslog/dmesg.last",	"var/nslog",
		"/var/nslog/icstats.out",	"var/nslog",

		# Files under /tmp
		"/tmp/fsck.log",		"var/log",
		"/tmp/savecore.log",	"var/log",

		# Files under /etc
		"/etc/*.conf",		        "etc",
		"/etc/hosts",			"etc",
		"/etc/localtime",		"etc",

		# Files under /var/nssynclog
		"/var/nssynclog/*.conf",	"var/nssynclog",
		"/var/nssynclog/sync_batch_status.log*",	"var/nssynclog",

		# Files under /var/nsproflog
		"/var/nsproflog/newproflog*",	"var/nsproflog",
		"/var/nsproflog/nsproflog*",	"var/nsproflog"
	);
	&log_debug_message("Copying messages,ns.log,dmesg and other log files ....\n");
	foreach my $fileset (keys(%files_to_be_copied))
	{
		#copy/syscopy routine from File::Copy does not take wildcards
		#copy("$fileset","$collector_abs_path/$files_to_be_copied{$fileset}") or
			##log_debug_message "Error in copying $fileset\n";
		`cp -p $fileset $collector_abs_path/$files_to_be_copied{$fileset} 2>/dev/null`;
	}
}


#######################################################################
# Copy vpn directory... check how useful it is...and call it later
########################################################################

sub copy_vpn_dir()
{
	`cp -p -R /var/vpn /var/tmp/support`; 
}

####################################################################
# Run BSD shell commands and capture the output
###################################################################

sub exec_shell_cmds()
{
	my $cmd;
	# Add the commands that need to be executed, in the following format
	#	<Command to be run>, <Output file to redirect the output>
	my %cmd_set = (
		"netstat -rn", "netstat-rn.out",
		"netstat -an", "netstat-an.out",
		"df -akin", "df-akin.out",
		"mount -v", "mount-v.out",
		"vmstat -m", "vmstat-m.out",
		"ps -auxwr", "ps-auxwr.out",
		"sysctl -a", "sysctl-a.out",
		"ifconfig -a", "ifconfig-a.out",
		"arp -a", "arp-a.out",
		"dmesg -a", "dmesg-a.out",
		"date", "date.out",
		"uname -a", "uname-a.out",
		"top -b 100", "top-b.out",
		"fstat", "fstat.out",
		"ls -lRtrp /flash", "ls_lRtrp_flash.out",
		"ls -lRtrp /var", "ls_lRtrp_var.out",
		"nsapimgr -B 'call haNodeDump'","nsapimgr_haNodeDump.out",
		"nsapimgr -d allvariables","nsapimgr_allvariables.out",
		"nsapimgr -d mappedip","nsapimgr_mappedip.out",
		"nsapimgr -d freeports","nsapimgr_freeports.out",
		"nsapimgr -d httprespbandstats","nsapimgr_httprespbandstats.out",
		"nsapimgr -d httpreqbandstats","nsapimgr_httpreqbandstats.out",
		"nsapimgr -d httprespbandrate","nsapimgr_httprespbandrate.out",
		"nsapimgr -d httpreqbandrate","nsapimgr_httpreqbandrate.out",
		"atacontrol list","atacontrol_list.out",
		"uptime","uptime.out",
		"head -10 $0","showtech_info.out",	#Get the first 10 lines of this script to get the revision info
		"crontab -l","crontab-l.out",
		"pb_policy","pitboss_policy.out",
		"nsp query","nsp.out",
		"nsp nsnetsvc query","nsp_nsnetsvc.out",
		"ntpq -p","ntpq-p.out"
	);

	# Define a set of version specific commands to be executed in FBSD 4.9 based systems. 
	# Here we do not know how many channels are there. Just run on 4 channels. The ones where there
	# is no device attached will have empty output
	my %cmd_set_fbsd49 = (
		"atacontrol cap 0 0", "atacontrol_cap_0.out",
		"atacontrol cap 1 0", "atacontrol_cap_1.out",
		"atacontrol cap 2 0", "atacontrol_cap_2.out",
		"atacontrol cap 3 0", "atacontrol_cap_3.out"
	);

	# Define a set of version specific commands to be executed in FBSD 6.3 based systems
	my %cmd_set_fbsd63 = (
		"atacontrol cap $flash_device", "atacontrol_cap_$flash_device.out",
		"atacontrol cap $hd_device", "atacontrol_cap_$hd_device.out",
		"smartctl -a /dev/$hd_device", "smartctl_$hd_device.out"
	);

	&log_debug_message("Running shell commands ....\n");
	foreach $cmd (keys(%cmd_set)) {
		# Run the command and redirect the output into the corresponding file
		`$cmd > $collector_abs_path/shell/$cmd_set{$cmd} 2>&1`;
	}

	if ($ns_version < "9.0") {
		foreach $cmd (keys(%cmd_set_fbsd49)) {
			# Run the command and redirect the output into the corresponding file
			`$cmd > $collector_abs_path/shell/$cmd_set_fbsd49{$cmd} 2>&1`;
		}
	}
	else {
		foreach $cmd (keys(%cmd_set_fbsd63)) {
			# Run the command and redirect the output into the corresponding file
			`$cmd > $collector_abs_path/shell/$cmd_set_fbsd63{$cmd} 2>&1`;
		}
	}
}

####################################################################
# Run vtysh commands and capture the output
###################################################################

sub exec_vtysh_cmds()
{
	# Add the commands that need to be executed, in the following format
	#	<Command to be run>
	my @cmd_set = (
		"show version",
		"show interface",
		"show nsm client",
		"show ip route",
		"show ip protocols rip",
		"show ip protocols bgp",
		"show ip protocols ospf",
		"show ip rip database",
		"show ip rip interface",
		"show ip rip route",
		"show ip ospf route",
		"show ip ospf database",
		"show ip ospf interface",
		"show ip ospf neighbor detail",
		"show bgp ipv4 neighbors",
		"show ipv6 route",
		"show ipv6 protocols rip",
		"show ipv6 rip database",
		"show ipv6 rip interface",
		"show ipv6 ospf route",
		"show ipv6 ospf database",
		"show ipv6 ospf interface",
		"show ipv6 ospf neighbor detail",
		"show bgp ipv6 neighbors",
		"show ip bgp",
		"show ip bgp summary",
		"show bgp ipv6",
		"show bgp ipv6 summary",
		"show running-config",
		"show process"
	);

	&log_debug_message("Running vtysh commands ....\n");
	foreach my $cmd (@cmd_set) {
		# Run the command and redirect the output into the corresponding file
		`echo "------------------------------\n" >> $collector_abs_path/shell/vtyshcmds.txt 2>&1`;
		`echo "vtysh -e \\\"$cmd\\\"" >> $collector_abs_path/shell/vtyshcmds.txt 2>&1`;

		`vtysh -e \"$cmd\" >> $collector_abs_path/shell/vtyshcmds.txt 2>&1`;
	}
}

####################################################################
# Run NetScaler CLI show commands and capture the output
###################################################################

sub
exec_show_cmds()
{
	my $tmp_file;

	my @showcmds = ( 
		"show hardware\n",
		"show server\n",
		"show ha node\n",
		"show service\n",
		"show service -internal\n",
		"show serviceGroup\n",
		"show vserver\n",
		"show monitor\n",
		"show vlan\n",
		"show interface\n",
		"show channel\n",
		"show lacp\n",
		"show location\n",
		"show locationparameter\n",
		"show locationfile\n",
		"show route\n",
		"show aaa user\n",
		"show aaa group\n",
		"show aaa radiusparams\n",
		"show aaa ldapparams\n",
		"show aaa tacacsparams\n",
		"show aaa nt4params\n",
		"show aaa certparams\n",
		"show aaa parameter\n",
		"show aaa session\n",
		"show audit syslogaction\n",
		"show audit syslogpolicy\n",
		"show audit syslogparams\n",
		"show audit nslogaction\n",
		"show audit nslogpolicy\n",
		"show audit nslogparams\n",
		"show audit messages\n",
		"show authentication radiusaction\n",
		"show authentication ldapaction\n",
		"show authentication tacacsaction\n",
		"show authentication certaction\n",
		"show authentication nt4action\n",
		"show authentication localpolicy\n",
		"show authentication radiuspolicy\n",
		"show authentication certpolicy\n",
		"show authentication ldappolicy\n",
		"show authentication tacacspolicy\n",
		"show authentication nt4policy\n",
		"show authorization policy\n",
		"show cache policy\n",
		"show cache global\n",
		"show cache contentgroup\n",
		"show cache forwardProxy\n",
		"show cache selector\n",
		"show cache object\n",
		"show cache parameter\n",
		"show cli mode\n",
		"show cli prompt\n",
		"show cmp action\n",
		"show cmp policy\n",
		"show cmp global\n",
		"show cr policy\n",
		"show cr vserver\n",
		"show cs policy\n",
		"show cs vserver\n",
		"show dns addRec\n",
		"show dns cnameRec\n",
		"show dns mxRec\n",
		"show dns nsRec\n",
		"show dns parameter\n",
		"show dns soaRec\n",
		"show dns suffix\n",
		"show dns nameserver\n",
		"show dos policy\n",
		"show filter action\n",
		"show filter policy\n",
		"show filter global\n",
		"show gslb site\n",
		"show gslb service\n",
		"show gslb vserver\n",
		"show gslb binding\n",
		"show gslb parameter\n",
		"show gslb policy\n",
		"show lb group\n",
		"show lb vserver\n",
		"show lb route\n",
		"show arp\n",
		"show vrID\n",
		"show bridgetable\n",
		"show ns config\n",
		"show ns hostname\n",
		"show ns acl\n",
		"show ns feature\n",
		"show ns info\n",
		"show ns ip\n",
		"show ns mode\n",
		"show fis\n",
		#"show ci\n", #This is shown in the output of "show node"
		"show ns license\n",
		"show rnat\n",
		"show route\n",
		"show ns spparams\n",
		"show ns tcpbufparam\n",
		"show ns tcpparam\n",
		"show ns version\n",
		"show ns weblogparam\n",
		"show ns rateControl\n",
		"show ns rpcnode\n",
		"show policy expression\n",
		"show policy map\n",
		#"show pq binding\n", #TODO: This requires a vserver as an argument
		"show pq policy\n",
		"show rewrite policy\n",
		"show rewrite action\n",
		"show rewrite global\n",
		"show rewrite param\n",
		"show router ospf\n",
		"show ospf route\n",
		"show router rip\n",
		#"show router bgp\n", #TODO: This requires an argument
		"show snmp alarm\n",
		"show snmp community\n",
		"show snmp manager\n",
		"show snmp mib\n",
		"show snmp trap\n",
		"show snmp oid vserver\n",
		"show snmp oid service\n",
		"show snmp oid servicegroup\n", #This works only in >= 9.0
		"show sc parameter\n",
		"show sc policy\n",
		"show ssl certkey\n",
		"show ssl certlink\n",
		"show ssl cipher\n",
		"show ssl crl\n",
		"show ssl fips\n",
		"show ssl fipskey\n",
		#"show ssl service\n", #This requires an argument
		#"show ssl vserver\n", #This requires an argument
		"show ssl wrapkey\n",
		"show ssl parameter\n",
		"show ssl action\n",
		"show ssl global\n",
		"show ssl ocspResponder\n",
		"show ssl policy\n",
		"show system cmdPolicy\n",
		"show system user\n",
		"show system group\n",
		"show system global\n",
		"show tunnel trafficpolicy\n",
		"show tunnel global\n",
		"show vpn vserver\n",
		"show vpn intranetapplication\n",
		"show vpn global\n",
		"show vpn trafficpolicy\n",
		"show vpn trafficaction\n",
		"show vpn url\n",
		"show vpn sessionpolicy\n",
		"show vpn sessionaction\n",
		"show vpn parameter\n",
		"show runningconf\n",
		"show ns ip6\n",
		"show route6\n",
		"show acl6\n",
		"show nd6\n",
		"show vrid6\n",
		"show ntp server\n",
		"show ntp sync\n"
	);

	#Add each interface to the list
	my @temp_iface_output=`nscli -U %%:.:. show interface 2>&1`;
	foreach(@temp_iface_output) {
		if (/Interface /) {
			my $tmp_str;
			$tmp_str=(split /Interface /)[1];
			$tmp_str=(split(/\(/,$tmp_str))[0];
			push(@showcmds, "show interface $tmp_str\n");
		}
	}

	# Create a temporary file to store all the commands
	$tmp_file = "$collector_abs_path/shell/showcmds.tmp";
	open (FILE,"> $tmp_file") || die "Error in creating $tmp_file!!\n\n";
	print FILE @showcmds;
	close(FILE);

	# Now run all the commands through nscli and redirect the output
	&log_debug_message("Running CLI show commands ....\n");
	open (FILE, ">$collector_abs_path/shell/showcmds.txt") || 
			die "Error in creating $collector_abs_path/shell/showcmds.txt!!\n\n";
	my $buf = `nscli -U %%:.:. batch -f $tmp_file 2>&1`; 
	print FILE "$buf"; 
	close(FILE); 

	unlink("$tmp_file");

	# Since some show commands display the encrypted passwords (show runningconfig for e.g.) 
	# we remove those lines 
	`egrep -v "set system user nsroot|add system user|set ns rpcNode" $collector_abs_path/shell/showcmds.txt > $support_dir/showcmds.$$`;
	`mv $support_dir/showcmds.$$ $collector_abs_path/shell/showcmds.txt`;
}

###########################################################################
# This function runs all "stat" commands and redirects the output to
# <collector's base dir>/shell/statcmds.txt.
###########################################################################

sub exec_stat_cmds()
{
	my $tmp_file;
	my @statcmds = (
		"stat service\n",
		"stat serviceGroup\n",
		"stat vlan\n",
		"stat interface\n",
		"stat aaa\n",
		"stat audit\n",
		"stat cache\n",
		"stat cmp\n",
		"stat cs vserver\n",
		"stat dns\n",
		"stat lb vserver\n",
		"stat ns\n",
		"stat bridge\n",
		"stat node\n",
		"stat ns acl\n",
		"stat protocol tcp\n",
		"stat protocol http\n",
		"stat protocol icmp\n",
		"stat protocol ip\n",
		"stat protocol udp\n",
		"stat snmp\n",
		"stat ssl\n",
		"stat vpn\n",
		"stat icmpv6\n",
		"stat acl6\n",
		"stat protocol ipv6\n"
	); 
	# Create a temporary file to store all the commands
	$tmp_file = "$collector_abs_path/shell/statcmds.tmp";
	open (FILE,"> $tmp_file") ||
				die "Error in creating $tmp_file!!\n\n";
	print FILE @statcmds;
	close(FILE);

	# Now run all the commands through nscli and redirect the output
	&log_debug_message("Running CLI stat commands ....\n");
	open (FILE, ">$collector_abs_path/shell/statcmds.txt") ||
				die "Error in creating $tmp_file!!\n\n";
	my $buf = `nscli -U %%:.:. batch -f $tmp_file 2>&1`; 
	print FILE "$buf"; 
	close(FILE); 

	unlink("$tmp_file");
}

###########################################################################
# This function copies all newnslog files
###########################################################################

sub copy_newnslog_files()
{
	my $file_index = 0;		#index of newnslog files (i.e.newnslog.$file_index)
	my $total_file_size; 	#A variable that keeps changing its value
	my @newnslog_files = (); # Array to hold the names of newnslog files
	my $count;				#count of number of files copied
	my $invalid_initial_val = 0;
	my $missing_files_ctr = 0; # count of missing newnslog.* files

	# If hard disk is not mounted, skip this step
	if ($hd_device eq "") {
		&log_debug_message("\t...Skipping collecting newnslog files as hard drive is not mounted!\n");
		return;
	}

	&log_debug_message("Determining newnslog files to archive....\n");
	chdir("/var/nslog");

	# Read the nslog.nextfile to determine where the logging is at now.
	if (-f "nslog.nextfile") {
		$file_index = `cat nslog.nextfile`;
		if ($file_index < 0 || $file_index > 100) {
			&log_debug_message("Invalid newnslog nextfile number in nslog.nextfile\n");
			&log_debug_message("Only one file \"newnslog\" will be copied!\n");
			$file_index = 0;
			$invalid_initial_val = 1;
		}
		else {  #This else part is just to print what file was the last created one
			&log_debug_message("\tLast newnslog file index=99\n") if $file_index == 0;
			my $tmp = $file_index - 1;
			&log_debug_message("\tLast newnslog file index=$tmp\n") if $file_index != 0;
		}
	}
	else {
		#If the file does not exist, set the invalid variable
		$invalid_initial_val = 1;
	}

	# After getting the latest file number, get the last 5 files besides the current 
	# file.

	# Start with the current file "newnslog"
	if (-f "newnslog") {
		@newnslog_files = ("newnslog");	#Add "newnslog" file to the array
		my @st = stat("newnslog");
		if (@st != qw//) { #Consider this only if non-empty list
			$total_file_size += $st[7];
			$count++;
		}
	}
	else {
		# Should this ever happen? Where will the process nsconmsg write to?
		&log_debug_message("\tWarning! Missing current newnslog file!\n");
	}

	# Since the newnslog files can be huge, we attempt to collect 5 files
	# subject to the total file size being less than MAX_FILESIZE_TOTAL (1.5 GB).

	$file_index--; # Decrement the file index; the nslog.nextfile has the next number

	#&log_debug_message("Before while loop.. .count=$count  index=$file_index total file size=$total_file_size Max=$MAX_FILESIZE_TOTAL\n");
	while ($count <= $NUM_FILES_TO_COLLECT && $total_file_size < $MAX_FILESIZE_TOTAL) {
		if (-f "newnslog.$file_index.gz" && -f "newnslog.$file_index") {
			my $tmp_file_name;
			#pick the latest of two files.
			$tmp_file_name = `ls -t newnslog.$file_index.gz newnslog.$file_index | head -1`;
			chomp($tmp_file_name);
			@newnslog_files = (@newnslog_files, "$tmp_file_name");
			my @st = stat("$tmp_file_name");
			if (@st != qw//) { #Consider this only if non-empty list
				$total_file_size += $st[7];
				$count++;
			}
		}
		elsif (-f "newnslog.$file_index.gz") {
			@newnslog_files = (@newnslog_files, "newnslog.$file_index.gz");
			my @st = stat("newnslog.$file_index.gz");
			if (@st != qw//) { #Consider this only if non-empty list
				$total_file_size += $st[7];
				$count++;
				#&log_debug_message("Inside while loop..file=newnslog.$file_index.gz count=$count  sz=$st[7] total filesize=$total_file_size\n");
			}

		}
		elsif (-f "newnslog.$file_index") {
			@newnslog_files = (@newnslog_files, "newnslog.$file_index");
			my @st = stat("newnslog.$file_index");
			if (@st != qw//) { #Consider this only if non-empty list
				$total_file_size += $st[7];
				$count++;
				#&log_debug_message("Inside while loop....file=newnslog.$file_index.gz count=$count  total file size=$total_file_size\n");
			}

		}
		else {
			&log_debug_message("\tWarning! Missing newnslog.$file_index or newnslog.$file_index.gz file!\n");
			$missing_files_ctr++;
			if ($missing_files_ctr >= 5) {
				last; #break out of the loop
			}
		}
			
		$file_index--;

		# Now, set the next file to be copied for the next iteration in the loop
		if ($file_index < 0) {
			if ($invalid_initial_val == 1) {
				# If we are here, it is because the nslog.nextfile was
				# corrupt and/or the value read from the file was not within
				# the bounds. We just break from the loop and stop collecting 
				# any more files.
				last;	#break out of the loop
			}
			$file_index = 99;
		}
	}
	#&log_debug_message("End of while loop .....count=$count total size=$total_file_size\n");
	&log_debug_message("\t... copied $count files from this directory.\n");

	# Now that we have collected the list of files, we need to be ready to archive
	# them. It is an expensive operation to copy them into the collector directory
	# We just link these files and use the correct tar option to copy the contents
	# into the archive.

	foreach my $name (@newnslog_files) {
		symlink("/var/nslog/$name","$collector_abs_path/var/nslog/$name") ||
			&log_debug_message("Error in creating a symbolic link for $name!\n");
	}
}

###########################################################################
# This function copies 5 files with pattern (passed as arg3), modified within 
# the last one week
#     arg1 - dir from which the files need to be looked at
#     arg2 - dir to which the files need to be copied to
#     arg3 - pattern that needs to be matched 
###########################################################################

sub copy_core_files()
{
	my @filelist;
	my $file;
	my $GAP_IN_SECONDS = $NUM_PREV_DAYS_FILES * 24 * 3600;

	# If hard disk is not mounted, skip this step
	if ($hd_device eq "") {
		&log_debug_message("\t...Skipping collecting $_[0] files as hard drive is not mounted!\n");
		return;
	}

	chdir($_[0]);

	# There are two ways to get the last few modified files in the last
	# one week. 
	# 1. To get the entire file list using glob and sort based on the 
	#    modified time. Then pick the last files if they are within the
	#    last 5 days
	# 2. A simpler way is to use ls -ltr command itself and pick the last
	#    5 files or just the "find" command with -mtime option
	#    The second option is more simple to implement, although it
	#    is running a shell command in Perl.
	# Option 1 is implemented here.

	&log_debug_message("Copying core files from $_[0] ...(last 5 files created within the last week)\n");
	#@filelist = <$_[2] [1-100]/$_[2]>; # This is not working for some reason, the range is not "from-to"
	@filelist = <$_[2] */$_[2]>;
	# Sort the existing files based on the modification time
	@filelist = sort {(stat($a))[9] <=> (stat($b))[9]} @filelist;

	# Create a dummy file and insert at the end. This is needed for comparision of modification times
	`touch xx`;
	my $xx_mtime = (stat("xx"))[9]; #Save the file xx's modification time
	@filelist = (@filelist, "xx"); #Insert xx at the end, needed for finding the last modified files

=begin comment
	# This is for debugging only - to print all files sorted
	foreach $file (@filelist) {
		my $difftime = ($xx_mtime - (stat($file))[9]);
		#&log_debug_message("%-25s diff=%-10ld 7daysGap=%-10ld",$file,$difftime,$GAP_IN_SECONDS);
		if ($difftime > $GAP_IN_SECONDS) {
			#&log_debug_message("  MORE THAN A WEEK OLD!\n");
		}
		else {
			#&log_debug_message("  WITHIN A WEEK OLD!\n");
		}
	}
=end comment
=cut

	# If the file "bounds" exists, just collect it anyway (by doing symlink)
	if (-f "bounds") {
		symlink("$_[0]/bounds","$_[1]/bounds") ||
				&log_debug_message("Error in creating a symbolic link for bounds!\n");
	}

	my $count = 0; #count of files that we have collected
	my $num_files_in_dir = scalar(@filelist);
	my $index = $num_files_in_dir - 2; #'xx is at the end, and index starts at 0

	# Traverse the file list backwards and get 5 files - the list is already sorted by last modified time
	# $filelist[0] has the earliest modified file and $filelist[$num_files_in_dir-1] has the
	# latest modified file (which should be "xx")

	while ($count < $NUM_FILES_TO_COLLECT && $index >= 0) {
		##log_debug_message "============= count=%d index=%d File/dir = %s\n",$count,$index,$filelist[$index];
		$_ = $filelist[$index];
		# In nCore systems, there will be a file called bounds. Ignore this file while traversing
		# NSPPE-* files are PE core files that should not be at the top level. Just in case they
		# are there, ignore.
		if (/bounds/ || /^NSPPE-/) {
			$index--;
			next; #don't increment $count here
		}

		# Look at only files and ignore directories
		if (-f $filelist[$index]) {
			my $file_mtime = (stat($filelist[$index]))[9];
			my $diff_mtime = $xx_mtime - $file_mtime;
			##log_debug_message "File=%s... mtime=%lu xx_mtime=%lu diff=%ld\n",$_,$file_mtime,$xx_mtime,$diff_mtime;
			# If the difference is less than 0 (negative), then date change must have happened on
			# this system. This file was created earlier and now the date has changed to an earlier date
			if ($diff_mtime < 0) {
				&log_debug_message("\tWarning! The file $_ has a date later than the current system date!\n");
			}
			elsif ($diff_mtime > $GAP_IN_SECONDS) {
				unlink("xx");
				##log_debug_message "Last sorted file reached.. breaking!\n";
				last;	#break out of the loop, as there won't be any more files within the last week
			}
			# Else, include this file. 
			##log_debug_message "...... Including this file... %s\n",$filelist[$index];

			# If this file/dir name has a path, split and get the basedir and the file name separately
			# Although File::Basename package is there with routines, this may be simpler in this context
			(my $dir, my $file) = split(/\//); # this works on $_, which is $filelist[$index]
			##log_debug_message "dir = %s   filename=%s\n",$dir,$file;

			# If after splitting, if $dir has a value and the $file is empty, then this is just a plain file
			# without any directory name in it.
			if ($dir ne "" && $file eq "") {
				symlink("$_[0]/$filelist[$index]","$_[1]/$filelist[$index]") ||
					&log_debug_message("Error in creating a symbolic link for $filelist[$index]!\n");
			}
			else {
				# If this is a NSPPE- core file, just warn and continue.. don't collect it
				# We are assuming that all these NSPPE- cores are within this subdirectories [1-100]
				if ($file =~ /^NSPPE-/) {
					&log_debug_message("\tNSPPE core ($_) file present! Skipping this file because of size restrictions..\n");
					$index--;
					next;
				}
				# If the directory does not exist, create that dir
				if (! -d "$_[1]/$dir") {
					##log_debug_message "%s does not exist! symlink %s, %s \n",$dir,$_[0],$_[1];
					mkdir("$_[1]/$dir") || &log_debug_message("Error in creating the directory $_[1]/$dir\n");
				}
				# Now create a symbolic link for the file
				symlink("$_[0]/$_","$_[1]/$_") ||
						&log_debug_message("Error in creating a symbolic link for %s under $dir,$_[1]\n");
			}
			$count++;
		}
		$index--;
	}
	unlink("xx");

	# Done finding out the last modified files! Present the info.
	if ($count == 0) {
		&log_debug_message("\t... Nothing to copy...No files created within the last one week!\n");
	}
	else {
		&log_debug_message("\t... copied $count files from this directory.\n");
	}
}

###########################################################################
# This function creates an archive of the collected files
###########################################################################

sub prepare_tar_archive()
{
	# If the hard drive is not present, create a README file warning this condition.
	if ($hd_device eq "") {
		my $tmp_file = "$collector_abs_path/README.no_hard_disk";
		open (FILE,"> $tmp_file") || &log_debug_message("Error in creating $tmp_file!!\n\n");
		print FILE "\nWarning! This techsupport archive was created when hard drive was not mounted in NetScaler.\n";
		print FILE "The newnslog files and core files were **NOT** collected as a result of this.\n";
		print FILE "The log files from /var/log were collected, but they come from MFS, not from the hard disk.\n";
		print FILE "Other relevant artifacts were collected.\n";
		print FILE "It's possible that the features may be disabled.\n\n";
		close(FILE);
	}
		
	chdir $support_dir || die "Could not chdir to $support_dir!!\n";
	&log_debug_message("Archiving all the data into \"$support_dir/$collector_base_dir.tar.gz\"....");
	`tar --create --force-local --atime-preserve --same-permissions --file $collector_base_dir.tar.gz --dereference --gzip $collector_base_dir 2>/dev/null`;
	&log_debug_message("Done.\n");
	
	my $old_support_archive = "$support_dir/support.tgz";
	if (-f $old_support_archive) {
		unlink($old_support_archive) || die "Could not unlink $old_support_archive";
	}

	if (symlink("$support_dir/$collector_base_dir.tar.gz",$old_support_archive)) {
		&log_debug_message("Created a symbolic link for the archive with $old_support_archive\n");
		&log_debug_message("$old_support_archive  ---- points to ---> $support_dir/$collector_base_dir.tar.gz\n");
	}

	# Create a symlink for the latest archive with the name called "latest". This is useful when many archives
	# are present, and "latest" points to the latest one.
	unlink("$support_dir/latest");
	symlink("$support_dir/$collector_base_dir","latest");

	# In the case of hard drive not being present, the archive is created in /flash/support.
	# Just create a symlink for the created archive in /var/tmp/support also
	if ($hd_device eq "") {
		unlink("$hd_support_dir/support.tgz");
		symlink("$support_dir/$collector_base_dir.tar.gz","$hd_support_dir/$collector_base_dir.tar.gz");
		symlink("$support_dir/$collector_base_dir.tar.gz","$hd_support_dir/support.tgz");
	}

	rmtree("$collector_abs_path",0,1);
}

########################################################################
# Helper function to get the current NetScaler version
##############################################################

sub get_ns_version()
{
	my $line;
	my @show_version = `nscli -U %%:.:. show version 2>&1`;

	foreach $line (@show_version) {
		$_ = $line;
		if (/NS/) {
			#Sample output format: "        NetScaler NS10.0: Build 10.004.cl, Date: Jul 10 2010, 16:24:57"
			chomp($_);
			($ns_version) = (split /NS/)[1];
			($ns_version) = (split(/:/,$ns_version))[0];
			&log_debug_message("NetScaler version $ns_version\n");
			return;
		}
	}
}

##########################################################
# Helper function to get the mounted flash and hard drives
##########################################################

sub get_hard_disk_device()
{
	# Get the hard disk device from df -k output
	$hd_device = `df -k | grep var`;
	# The output of the above shows like this:
	#     /dev/ad2s1e    69490770 3872132 60059378     6%    /var
	chomp($hd_device);

	# Check first if hard disk is mounted! If for whatever reason the hard disk is not
	# mounted, we need to alter what we collect
	if ($hd_device eq "") {
		&log_debug_message("\tWARNING!! HARD DISK IS NOT MOUNTED!!!\n");
		&log_debug_message("\tOnly relevant data will be collected!!\n");
	}
	else {
		$hd_device =~ s/ .*//; #Remove the output after the first blank (after ad2s1e)
		$hd_device =~ s/^\/dev\///; #Remove the "/dev/" string
		$hd_device =~ s/s[1-9].*//; #Remove the slice part of the device (s1e)
		#&log_debug_message("Hard disk = $hd_device\n");
	}

	# Get the flash disk device from df -k output
	$flash_device = `df -k | grep flash`;
	# The output of the above shows like this:
	#     /dev/ad0s1a      231774 194792 18442    91%    /flash
	chomp($flash_device);
	$flash_device =~ s/ .*//; #Remove the output after the first blank (after ad0s1a)
	$flash_device =~ s/^\/dev\///; #Remove the "/dev/" string
	$flash_device =~ s/s[1-9].*//; #Remove the slice part of the device (s1e)
	#&log_debug_message("Flash disk = $flash_device\n");
}

########################################################################
# Helper function to log the log_debug_messages onto console and into log files using syslog
########################################################################

sub log_debug_message()
{
	my $log_msg = $_[0];

	printf "$log_msg";
	syslog $syslog_level,"%s",$log_msg;
}
