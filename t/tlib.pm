package tlib;
use File::Basename qw/dirname/;
no strict 'refs';

sub import {
    my ($pkg,$filename,$line) = caller();
    my $yars_exe = $^X.' '.dirname($filename).'/../blib/script/yars';
    *{"$pkg".'::sys'} = sub {
        my $cmd = shift;
        $ENV{PERL5LIB} = join ':', @INC;
        $cmd =~ s/\byars(?= )/$yars_exe/;
        system($cmd)==0 or die "Error running $cmd : $!";
    }
};

1;

