use FindBin;
use lib "$FindBin::Bin";
use BER;
use SNMP_util;
use SNMP_Session;
use Cwd;
$MIB1 = ".1.3.6.1.4.1.232.9.2.5.1.1.5.2";
$HOST = "localhost";
($value) = &snmpget("$HOST","$MIB1");
$path="$INC[0]";
#print $path;
if ($value) { 
#$var="cscript \"C:/Program Files/HP OpenView/Installed Packages/{790C06B4-844E-11D2-972B-080009EF8C2A}/bin/instrumentation/WINOSSPI_CreateServices.js\" RILOE $value //Nologo";
$var="cscript \"$path/WINOSSPI_CreateServices.js\" RILOE $value //Nologo";
system($var);
}

