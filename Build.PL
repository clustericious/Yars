#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Yars',
    license             => 'perl',
    dist_abstract       => "Yars Server",
    dist_version_from   => 'lib/Yars.pm',
    build_requires => {
        'Test::More'                  => 0,
        'Clustericious'               => '0.59',
        'Clustericious::Config'       => 0,
        'Clustericious::RouteBuilder' => 0,
        'Test::Pod::Coverage'         => 0,
    },
    add_to_cleanup      => [ 'Yars-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();

1;
