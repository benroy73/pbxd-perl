#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'       => 'PBX::DEFINITY',
    'PREREQ_PM'  => {
        "Expect"                => 0,
        "Term::VT102"           => 0,
        "XML::Simple"           => 0,
        "Data::Dumper"          => 0,
    },
);
