#!/usr/bin/perl -w
# cgi-bin/ice_cream: program to answer and generate ice cream
# order form (version 4)
use strict; # enforce variable declarations and quoting
use CGI qw(:standard);

print header, start_html("Ice Cream Stand"), h1("Ice Cream Stand");
if (param()) { # the form has already been filled out
    my $who = param("name");
    my $flavor = param("flavor");
 my $scoops = param("scoops");
 my $taxrate = 1.0743;
 my $cost = sprintf("%.2f", $taxrate * (1.00 + $scoops * 0.25));
 print p("Ok, $who, have $scoops scoops of $flavor for \$$cost.");
} else { # first time through, so present clean form
    print hr(); # draw a horizontal rule before the form
    print start_form();
    print p("What's your name? ", textfield("name"));
    # FOR EXPLANATION OF FOLLOWING TWO LINES, SEE NEXT SECTION
    print p("What flavor: ", popup_menu("flavor", 
                                           ['mint','cherry','mocha']));
    print p("How many scoops? ", popup_menu("scoops", [ 1..3 ]));
    print p(submit("order"), reset("clear"));
    print end_form(), hr();
}
print end_html;
