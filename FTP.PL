
use Net::FTP;


$ftp = Net::FTP->new("ftp.google.com", Timeout => 10)
        or die "Could not connect.\n";


$username = "anonymous";
$password = "admin";



$ftp->login($username, $password)
        or die "Could not log in.\n";


$ftp->cwd('/pub/test');


$remotefile = "main.html";
$localfile = "output.txt";


$ftp->get($remotefile, $localfile)
        or die "Can not get file.\n";

