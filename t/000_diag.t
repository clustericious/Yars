use strict;
use warnings;
use Test::More tests => 1;

BEGIN { eval q{ use EV } }

my @modules = sort qw(
  Mojolicious
  Clustericious
  Clustericious::Config
  Clustericious::Log
  Number::Bytes::Human
  File::HomeDir
  Yars::Client
  Test::Clustericious::Cluster
  EV
  Monkey::Patch
);

pass 'okay';

diag '';
diag '';
diag '';

diag sprintf "%-30s %s", 'perl', $^V;

foreach my $module (@modules)
{
  if(eval qq{ use $module; 1 })
  {
    my $ver = eval qq{ \$$module\::VERSION };
    $ver = 'undef' unless defined $ver;
    diag sprintf "%-30s %s", $module, $ver;
  }
  else
  {
    diag sprintf "%-30s none", $module;
  }
}

diag '';
diag '';
diag '';

