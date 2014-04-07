
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Yet Another RESTful-Archive Service",
  "AUTHOR" => "Graham Ollis <plicease\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Yars",
  "EXE_FILES" => [
    "bin/yars",
    "bin/yars_disk_scan",
    "bin/yars_fast_balance",
    "bin/yars_generate_diskmap"
  ],
  "LICENSE" => "perl",
  "NAME" => "Yars",
  "PREREQ_PM" => {
    "Clustericious" => "0.9925",
    "Clustericious::Commands" => 0,
    "Clustericious::Config" => "0.21",
    "Clustericious::Log" => "0.11",
    "Digest::file" => 0,
    "File::Find::Rule" => 0,
    "File::HomeDir" => "0.91",
    "Filesys::Df" => 0,
    "Hash::MoreUtils" => 0,
    "JSON::XS" => 0,
    "List::MoreUtils" => 0,
    "Log::Log4perl" => 0,
    "Log::Log4perl::CommandLine" => 0,
    "Mojolicious" => "4.00",
    "Number::Bytes::Human" => "0.09",
    "Smart::Comments" => 0,
    "Yars::Client" => "0.90"
  },
  "TEST_REQUIRES" => {
    "Capture::Tiny" => 0,
    "Test::Clustericious::Cluster" => "0.08",
    "Test::Clustericious::Config" => 0,
    "Test::Clustericious::Log" => 0,
    "Test::More" => 0,
    "YAML::XS" => 0
  },
  "VERSION" => "0.95",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Capture::Tiny" => 0,
  "Clustericious" => "0.9925",
  "Clustericious::Commands" => 0,
  "Clustericious::Config" => "0.21",
  "Clustericious::Log" => "0.11",
  "Digest::file" => 0,
  "File::Find::Rule" => 0,
  "File::HomeDir" => "0.91",
  "Filesys::Df" => 0,
  "Hash::MoreUtils" => 0,
  "JSON::XS" => 0,
  "List::MoreUtils" => 0,
  "Log::Log4perl" => 0,
  "Log::Log4perl::CommandLine" => 0,
  "Mojolicious" => "4.00",
  "Number::Bytes::Human" => "0.09",
  "Smart::Comments" => 0,
  "Test::Clustericious::Cluster" => "0.08",
  "Test::Clustericious::Config" => 0,
  "Test::Clustericious::Log" => 0,
  "Test::More" => 0,
  "YAML::XS" => 0,
  "Yars::Client" => "0.90"
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



