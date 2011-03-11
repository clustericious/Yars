#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::MBD;

ok Test::MBD::stop, "stopped, cleaned up db";

1;
