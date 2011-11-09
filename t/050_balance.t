#!perl

# t/050_balance.t

# TODO: logging doesn't work quite right in this test;
# balancer logs are in /tmp/yars.test*.log instead of stderr.
# (when LOG_LEVEL is e.g. TRACE)

use strict;
use warnings;
use File::Basename qw/dirname/;
use File::Temp;
use Test::More;
use Test::Mojo;
use File::Path qw/mkpath/;
use Mojo::ByteStream qw/b/;

use Yars::Balancer;

my $test_files = 10;
my $root = File::Temp->newdir(CLEANUP => 1);
my $t = Test::Mojo->new("Yars");
my $conf = $t->app->config;

$conf->servers( default => [{
            url   => "http://localhost:9050", # notused
            disks => [
                { root => "$root/one",   buckets => [ qw/0 1 2 3 4 5 6 7/ ] },
                { root => "$root/two",   buckets => [ qw/8 9 A B C D E F/ ] },
            ]}]);
$conf->{balance_delay} = 1;
my $temp = File::Temp->new(UNLINK => 0);
$conf->{url} = "http://localhost:9050"; # not used

$t->get_ok('/'."got /");

mkpath "$root/two";
ok chmod 0555, "$root/two", "chmod 0555 $root/two";

my $ua = Mojo::UserAgent->new();
$ua->ioloop(Mojo::IOLoop->singleton);

my ($one,$two) = (0,0);
for my $i (1..$test_files) {
    my $content = "content $i";
    $t->put_ok("/file/filename_$i", {}, $content)->status_is(201);
    for (b($content)->md5_sum) {
        /^[0-7]/i and $one++;
        /^[89ABCDEF]/i and $two++;
    }
}

ok chmod 0775, "$root/two", "chmod 0775 $root/two";

my $json = $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json;
is $json->{"$root/one"}{count}, $test_files;
is $json->{"$root/two"}{count}, 0;

# Now balance!
Yars::Balancer->start_balancers($t->app);
sleep 10;

$json = $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json;
is $json->{"$root/one"}{count}, $one;
is $json->{"$root/two"}{count}, $two;

Yars::Balancer->stop_balancers($t->app);

done_testing();

