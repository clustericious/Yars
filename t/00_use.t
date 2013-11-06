use strict;
use warnings;
use Log::Log4perl::CommandLine ();
use Test::More tests => 6;

use_ok 'Yars::Command::yars_disk_scan';
use_ok 'Yars::Command::yars_fast_balance';
use_ok 'Yars::Command::yars_generate_diskmap';
use_ok 'Yars::Tools';
use_ok 'Yars::Routes';
use_ok 'Yars';
