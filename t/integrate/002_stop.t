#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw/dirname/;
use Test::More;

$ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
$ENV{PERL5LIB} = join ':', @INC;
$ENV{PATH} = dirname(__FILE__)."/../../blib/script:$ENV{PATH}";
#$ENV{LOG_LEVEL} = "TRACE";
$ENV{YARS_TMP_ROOT} = "/dev/null";

sub _sys {
    my $cmd = shift;
    system($cmd)==0 or die "Error running $cmd : $!";
}

_sys("YARS_WHICH=1 yars stop");
_sys("YARS_WHICH=2 yars stop");
sub _slurp {
    my $file = shift;
    my @lines = IO::File->new("<$file")->getlines;
    return join '', @lines;
}
for my $which (qw/1 2/) {
    my $pid_file = "/tmp/yars_${which}_hypnotoad.pid";
    my $success = (! -e $pid_file || kill 0, _slurp($pid_file));
    ok $success, "stopped server $which";
    diag "Stopped server $which" if $success;
};


done_testing();

1;
