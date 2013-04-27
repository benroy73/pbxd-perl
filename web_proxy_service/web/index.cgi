#!/usr/bin/perl
use strict;
use CGI qw(:standard);

print header;

print <<END_HTML;
<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>pbxd web service versions</title>
</head>
<body>
    <h2>pbxd web service versions</h2>
    <ul>
END_HTML

opendir(DIR, ".");
my @files = readdir(DIR);
closedir(DIR);

foreach my $dir (@files) {
    if (-d $dir  &&  $dir !~ /^\.|^PERL-INF|^META-INF/ ) {
        print "<li><a href=\"$dir\">$dir</a></li>\n";
    }
}

print <<END_HTML;
    </ul>
</body>
</html>
END_HTML
