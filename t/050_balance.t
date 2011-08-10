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
use Mojo::ByteStream qw/b/;

my $t = Test::Mojo->new("Yars");

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

$t->get_ok("/stats/files_by_disk?count=1&df=0")->status_is(200)
  ->json_content_is( { "$root/one" => { count => $test_files },
                       "$root/two" => { count => 0 } });

# Now balance!
Mojo::IOLoop->timer(10 => sub { Mojo::IOLoop->stop; });
$ua->ioloop->start;

$t->get_ok("/stats/files_by_disk?count=1&df=0")->status_is(200)
  ->json_content_is( { "$root/one" => { count => $one },
                       "$root/two" => { count => $two } } );

done_testing();

