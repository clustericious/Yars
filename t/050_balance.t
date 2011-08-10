#!perl

# t/050_balance.t

use strict;
use warnings;

my $test_files = 10;
my $root;

BEGIN {
    use File::Basename qw/dirname/;
    use File::Temp;
    $ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf4';
    $ENV{YARS_TMP_ROOT} = $root = File::Temp->newdir(CLEANUP => 1);
    $ENV{LOG_LEVEL} = 'FATAL';
}

use Test::More;
use Test::Mojo;
use File::Path qw/mkpath/;

my $t = Test::Mojo->new("Yars");

$t->get_ok('/'."got /");

mkpath "$root/two";
ok chmod 0555, "$root/two", "chmod 0555 $root/two";

my $ua = Mojo::UserAgent->new();
$ua->ioloop(Mojo::IOLoop->singleton);

for my $i (1..$test_files) {
    $t->put_ok("/file/filename_$i", {}, "content $i")->status_is(201);
}

ok chmod 0775, "$root/two", "chmod 0775 $root/two";

Mojo::IOLoop->timer(20 => sub { Mojo::IOLoop->stop; });

$ua->ioloop->start;

done_testing();

