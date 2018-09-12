#!/usr/bin/perl -w
%words = qw(
	george	camel
	tom		llama
	louise	alpaca
	helen	alpaca
	flo		moose
);
print "Who are you? ";
$name = <STDIN>;
chomp ($name);
$original_name = $name;
$name =~ s/\W.*//;
$name =~ tr/A-Z/a-z/;
if ($name eq "michael") {
	print "Good morning, your Highness!\n";
} else {
	print "Hello, $original_name\n";
	$secretword = $words{$name};
	if ($secretword eq "") {
		$secretword = "groucho";
	}
	print "What's the secret word? ";
	$guess = <STDIN>;
	chomp ($guess);
	while ($guess ne $secretword) {
		print "Wrong, try again: " ;
			$guess = <STDIN>;
			chomp ($guess);
	}
}



