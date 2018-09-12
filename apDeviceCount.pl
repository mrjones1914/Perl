

open(RADIO, $ARGV[0])  || die "Cannot open file: $!";
while ( <RADIO> )  {
	chomp $_;
	$totalNumberdevices = 0;
	$totalNumberdevices = split(/\s*:\s*/, $totalNumberdevices);
	$totalNumberdevices = `snmpget -c BlueBird59 $_ .iso.org.dod.internet.private.enterprises.norand.manage.norandNET.nBridge.bridgeStats.0`;
	    	print "$_ : The number of devices under this radio is $totalNumberdevices\n";
           	next;
     		
}