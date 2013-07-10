use strict;
use warnings;
use Yars::Tools;
use Test::More tests => 1;

my $tools = Yars::Tools->new;
isa_ok $tools->_ua, 'Mojo::UserAgent';
