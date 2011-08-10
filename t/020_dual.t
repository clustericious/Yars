#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw/dirname/;
use Test::More;
use Mojo::ByteStream qw/b/;
use Yars;

my @urls = ("http://localhost:9051","http://localhost:9052");

$ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf2';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
$ENV{PERL5LIB} = join ':', @INC;
$ENV{PATH} = dirname(__FILE__)."/../blib/script:$ENV{PATH}";
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);
#$ENV{LOG_LEVEL} = "TRACE";

sub _sys {
    my $cmd = shift;
    system($cmd)==0 or die "Error running $cmd : $!";
}

sub _slurp {
    my $file = shift;
    my @lines = IO::File->new("<$file")->getlines;
    return join '', @lines;
}

for my $which (qw/1 2/) {
    my $pid_file = "/tmp/yars_${which}_hypnotoad.pid";
    if (-e $pid_file && kill 0, _slurp($pid_file)) {
        diag "killing running yars $which";
        _sys("LOG_FILE=/tmp/yars_test.log YARS_WHICH=$which yars stop");
    }
    _sys("LOG_FILE=/tmp/yars_test.log YARS_WHICH=$which yars start");
}
my $ua = Mojo::UserAgent->new();
$ua->max_redirects(3);
is $ua->get($urls[0].'/status')->res->json->{server_url}, $urls[0], "started first server at $urls[0]";
is $ua->get($urls[1].'/status')->res->json->{server_url}, $urls[1], "started second server at $urls[1]";

my $i = 0;
my @contents = <DATA>;
my @locations;
my @digests;
my @filenames;
for my $content (@contents) {
    $i++;
    my $filename = "file_numero_$i";
    push @filenames, $filename;
    push @digests, b($content)->md5_sum;
    my $tx = $ua->put("$urls[1]/file/$filename", {}, $content);
    my $location = $tx->res->headers->location;
    ok $location, "Got location header";
    ok $tx->success, "put $filename to $urls[1]/file/filename";
    push @locations, $location;
}

for my $url (@locations) {
    my $content = shift @contents;
    my $filename = shift @filenames;
    my $md5 = shift @digests;
    next unless $url; # error will occur above
    {
        my $tx = $ua->get($url);
        my $res;
        ok $res = $tx->success, "got $url";
        is $res->body, $content, "content match";
    }
    {
        my $tx = $ua->head("$urls[0]/file/$md5/$filename");
        ok $tx->success, "head $urls[0]/file/$md5/$filename";
    }
    {
        my $tx = $ua->delete("$urls[0]/file/$md5/$filename");
        ok $tx->success, "delete $urls[0]/file/$md5/$filename";
        diag join ',',$tx->error if $tx->error;
    }
    {
        my $tx = $ua->get("$urls[0]/file/$md5/$filename");
        is $tx->res->code, 404, "Not found after deleting";
        $tx = $ua->get("$urls[1]/file/$md5/$filename");
        is $tx->res->code, 404, "Not found after deleting";
    }
}

# Ensure that only one balancer is running.
my $got = Mojo::Asset::File->new(path => '/tmp/yars_balancers.test')->slurp;
my $json = Mojo::JSON->new->decode($got);
ok ( (keys %$json)==1, "One balancer is running" );

for (keys %$json) {
    ok ( (kill 0, $_), "pid $_ is running");
}

_sys("YARS_WHICH=1 yars stop");
_sys("YARS_WHICH=2 yars stop");

done_testing();

__DATA__
this is one file
this is another file
this is a third file
these files are all different
no two are the same
and some of them have md5s that make them go to
the first server, while others go to the
second server.
Every file is one line long.
buh bye
