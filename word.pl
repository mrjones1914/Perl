#!/usr/bin/perl -w

sub good_word {
    my($somename,$someguess) = @_; # name the parameters
    $somename =~ s/\W.*//; # get rid of everything after first word
    $somename =~ tr/A-Z/a-z/; # lowercase everything
    if ($somename eq "michael") { # should not need to guess
        return 1; # return value is true
    } elsif (($words{$somename} || "groucho") eq $someguess) {
        return 1; # return value is true
    } else {
        return 0; # return value is false
    }
}