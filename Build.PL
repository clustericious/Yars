#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build::Database;

my $builder = Module::Build::Database->new(
    database_type       => "PostgreSQL",
    database_options => {
        name => "restas::yarsserver",
        schema => "restas::yarsschema",
    },
    module_name         => 'RESTAS::Yars',
    license             => 'perl',
    dist_abstract       => "RESTAS::Yars server",
    dist_version_from   => 'lib/RESTAS/Yars.pm',
    build_requires => {
        'Test::More'          => 0,
        'Clustericious'       => '0.04',
        'Test::Pod::Coverage' => 0,
        'Rose'                => 0,
        'DBD::Pg'             => 0,
        'Rose::Planter'       => '0.04',
    },
    add_to_cleanup      => [ 'RESTAS::Yars-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();

1;
