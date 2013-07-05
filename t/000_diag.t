use strict;
use warnings;
use Test::More;

plan skip_all => 'turned off';

my @mod_list = qw(
  Clustericious
  Clustericious::Config
  Clustericious::Log
  Data::Dumper
  File::HomeDir
  Filesys::Df
  Hash::MoreUtils
  JSON::XS
  List::MoreUtils
  Log::Log4perl
  Log::Log4perl::CommandLine
  Mojolicious
  Number::Bytes::Human
  Smart::Comments
  Try::Tiny
  Yars::Client
);

plan tests => scalar @mod_list;

diag "";
diag "$^X $^V";
diag "% uname -a";
diag `uname -a`;
if($^O eq 'linux')
{
  diag "% free";
  diag `free`;
}
if($^O =~ /bsd$/)
{
  diag "% sysctl hw.physmem";
  diag `sysctl hw.physmem`;
}

foreach my $mod (@mod_list)
{
  use_ok $mod;
  my $version = eval qq{ \$${mod}::VERSION } // 'unknown';
  diag "$mod $version";
}