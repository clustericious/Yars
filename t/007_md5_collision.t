use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }

use File::HomeDir::Test;
use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

$ENV{LOG_LEVEL} = 'FATAL';

my $t = Test::Mojo->new('Yars');
my $root = File::Temp->newdir(CLEANUP => 1);
$t->app->config->servers(
    default => [{
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->app_url;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $one = <<ONE;
d131dd02c5e6eec4693d9a0698aff95c 2fcab58712467eab4004583eb8fb7f89
55ad340609f4b30283e488832571415a 085125e8f7cdc99fd91dbdf280373c5b
d8823e3156348f5bae6dacd436c919c6 dd53e2b487da03fd02396306d248cda0
e99f33420f577ee8ce54b67080a80d1e c69821bcb6a8839396f9652b6ff72a70
ONE

my $two = <<TWO;
d131dd02c5e6eec4693d9a0698aff95c 2fcab50712467eab4004583eb8fb7f89
55ad340609f4b30283e4888325f1415a 085125e8f7cdc99fd91dbd7280373c5b
d8823e3156348f5bae6dacd436c919c6 dd53e23487da03fd02396306d248cda0
e99f33420f577ee8ce54b67080280d1e c69821bcb6a8839396f965ab6ff72a70
TWO

$one =~ tr/0-9a-f//dc;
$two =~ tr/0-9a-f//dc;
$one = pack('H*',$one);
$two = pack('H*',$two);

ok $one ne $two, "Strings differ";
is b($one)->md5_sum->to_string, b($two)->md5_sum->to_string, "MD5s the same";

$t->put_ok("/file/one", {}, $one)->status_is(201);  # created
$t->put_ok("/file/one", {}, $two)->status_is(409);  # conflict

done_testing();

1;

