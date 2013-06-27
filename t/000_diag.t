use strict;
use warnings;
use Test::More tests => 1;

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
diag "% ulimit -a";
diag `sh -c 'ulimit -a'`;

pass 'okay';
