package My::ModuleBuild;

use strict;
use warnings;
use base qw( Module::Build );

sub new
{
  my($class, %args) = @_;

  use YAML ();
  print YAML::Dump(\%args);
  
  $class->SUPER::new(%args);
}

1;
