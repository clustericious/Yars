#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Yars',
    license             => 'perl',
    dist_abstract       => "Yars Server",
    dist_version_from   => 'lib/Yars.pm',
    dist_author         => q{Brian Duggan <brian.duggan@nasa.gov>},
    build_requires => {
        'Test::More'                  => 0,
        'Mojolicious'                 => '2.62',
        'Clustericious'               => '0.97',
        'Clustericious::Config'       => '0.07',
        'Clustericious::Log'          => 0,
        'Digest::file'                => 0, # in core
        'Try::Tiny'                   => 0,
        'Test::Pod::Coverage'         => 0,
        'List::MoreUtils'             => 0,
        'List::Util'                  => 0,
        'File::Find'                  => 0,
        'File::Find::Rule'            => 0,
        'File::Copy'                  => 0,
        'Filesys::Df'                 => 0,
        'File::Compare'               => 0,
        'Hash::MoreUtils'             => 0,
    },
    add_to_cleanup      => [ 'Yars-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();

1;
