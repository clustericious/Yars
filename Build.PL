#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'RESTAS::Yars',
    license             => 'perl',
    dist_abstract       => "RESTAS::Yars server",
    dist_version_from   => 'lib/RESTAS/Yars.pm',
    build_requires => {
        'Test::More'          => 0,
        'Clustericious'       => '0.04',
        'Test::Pod::Coverage' => 0,
    },
    add_to_cleanup      => [ 'RESTAS::Yars-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();

1;
