
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Yet Another RESTful-Archive Service",
  "AUTHOR" => "Graham Ollis <plicease\@cpan.org>",
  "BUILD_REQUIRES" => {
    "Mojo::IOLoop" => 0,
    "Mojolicious" => 0,
    "Test::More" => 0,
    "YAML::XS" => 0
  },
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
    "Clustericious::Config" => "0.20",
    "Clustericious::Log" => 0,
    "Digest::file" => 0,
    "Fcntl" => 0,
    "File::Find::Rule" => 0,
    "File::HomeDir" => "0.91",
    "File::Path" => 0,
    "Filesys::Df" => 0,
    "Hash::MoreUtils" => 0,
    "JSON::XS" => 0,
    "List::MoreUtils" => 0,
    "Log::Log4perl" => 0,
    "Log::Log4perl::CommandLine" => 0,
    "Mojolicious" => "3.86",
    "Number::Bytes::Human" => "0.09",
    "Smart::Comments" => 0,
    "Try::Tiny" => 0,
    "Yars::Client" => "0.86"
  },
  "VERSION" => "0.84",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


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



