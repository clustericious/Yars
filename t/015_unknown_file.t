#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use File::Basename qw/dirname/;
    $ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf';
}

use Test::More;
use Test::Mojo;
use Yars;

my $t = Test::Mojo->new('Yars');

my $content = 'We\'re gonna be late for the lodge meeting Fred.';

$t->get_ok("/file/barney/5551212", {}, $content)->status_is(404);


done_testing();
