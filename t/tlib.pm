package tlib;
use File::Basename qw/dirname/;
no strict 'refs';

sub import {
    my ($pkg,$filename,$line) = caller();
    my $dir = dirname $filename;
    my $script = -f "$dir/../blib/script/yars" ? "$dir/../blib/script/yars" : "$dir/../bin/yars";
    my $yars_exe = "$^X $script";
    *{"$pkg".'::sys'} = sub {
        my $cmd = shift;
        $cmd =~ s/\byars(?= )/$yars_exe/;
        system($cmd)==0 or die "Error running $cmd : $!";
    }
};

1;

