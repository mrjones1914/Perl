#!/usr/bin/perl -w
init_words();
print "What is your name? ";
$name = <STDIN>;
chomp $name;
if ($name =~ /^michael\b/i) { # back to the other way :-)
    print "Good day, Your Highness!\n";
} else {
    print "Hello, $name!\n"; # ordinary greeting
    print "What is the secret word? ";
    $guess = <STDIN>;
    chomp ($guess);
    while (! good_word($name,$guess)) {
        print "Wrong, try again. What is the secret word? ";
        $guess = <STDIN>;
        chomp ($guess);
    }
}
## subroutines from here down
sub init_words {
    open (WORDSLIST, "wordslist") || 
                              die "can't open wordlist: $!";
    while ( defined ($name = <WORDSLIST>)) {
        chomp ($name);
        $word = <WORDSLIST>;
        chomp $word;
        $words{$name} = $word;
    }
    close (WORDSLIST) || die "couldn't close wordlist: $!";
}
sub good_word {
    my($somename,$someguess) = @_; # name the parameters
    $somename =~ s/\W.*//;         # delete everything after
                                   # first word
    $somename =~ tr/A-Z/a-z/;      # lowercase everything
    if ($somename eq "randal") {   # should not need to guess
        return 1;                  # return value is true
    } elsif (($words{$somename} || "groucho") eq $someguess) {
        return 1;                  # return value is true
    } else {
        return 0;                  # return value is false
    }
}