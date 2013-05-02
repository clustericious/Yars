
use strict;
use warnings;



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
    "bin/yars_fast_balance",
    "bin/yars_disk_scan",
    "bin/yars_generate_diskmap"
  ],
  "LICENSE" => "perl",
  "NAME" => "Yars",
  "PREREQ_PM" => {
    "Clustericious" => "0.97",
    "Clustericious::Commands" => 0,
    "Clustericious::Config" => "0.07",
    "Clustericious::Log" => 0,
    "Clustericious::RouteBuilder" => 0,
    "Data::Dumper" => 0,
    "Digest::file" => 0,
    "Fcntl" => 0,
    "File::Basename" => 0,
    "File::Compare" => 0,
    "File::Find::Rule" => 0,
    "File::Path" => 0,
    "File::Temp" => 0,
    "File::stat" => 0,
    "Filesys::Df" => 0,
    "FindBin" => 0,
    "Hash::MoreUtils" => 0,
    "IO::Dir" => 0,
    "JSON::XS" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "Log::Log4perl" => 0,
    "Log::Log4perl::CommandLine" => 0,
    "Mojo::Base" => 0,
    "Mojo::ByteStream" => 0,
    "Mojolicious" => "3.86",
    "Smart::Comments" => 0,
    "Try::Tiny" => 0,
    "Yars::Client" => 0
  },
  "TEST_REQUIRES" => {
    "File::HomeDir" => 0,
    "File::HomeDir::Test" => 0,
    "File::Spec" => 0,
    "Mojolicious" => 0,
    "Scalar::Util" => 0,
    "Sys::Hostname" => 0,
    "Test::Mojo" => 0,
    "Test::More" => 0,
    "YAML" => 0
  },
  "VERSION" => "0.80",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



