#!/usr/bin/env perl

use Test::More;
use File::Path qw/rmtree/;
use strict;

ok 1;

#for my $file (glob "/tmp/yars.test.$<.*") {
#    -w $file or next;
#    -d $file and do { rmtree $file; next; };
#    ok unlink $file, "removed $file";
#}

done_testing();

1;

