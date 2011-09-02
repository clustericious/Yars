#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw/dirname/;
use Test::More;
use Mojo::ByteStream qw/b/;
use Yars;

my @urls = ("http://localhost:9051","http://localhost:9052");

$ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
$ENV{PERL5LIB} = join ':', @INC;
$ENV{PATH} = dirname(__FILE__)."/../../blib/script:$ENV{PATH}";
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);
$ENV{LOG_LEVEL} = "TRACE";

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

diag "Started server $urls[0]";
diag "Started server $urls[1]";

done_testing();

1;
