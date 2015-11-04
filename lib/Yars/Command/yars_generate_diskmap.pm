package Yars::Command::yars_generate_diskmap;

# PODNAME: yars_generate_diskmap
# ABSTRACT: generate a mapping from servers + hosts to buckets for yars.
# VERSION

=head1 SYNOPSIS

given hostdisk.txt:

 host1 /disk1
 host2 /disk2
 host2 /disk3

generate a yars disk map:

 % yars_generate_diskmap 2 hostdisk.txt > ~/etc/yars_disk_map.conf

then include from your Yars.conf file:

 ---
 % extend_config 'yars_disk_map.conf';

=head1 DESCRIPTION

This script generates a disk map for use with the Yars service.  The first argument is the
number of hex digits to use in prefixes, subsequent arguments are files where each line
contains a hostname and a path to use for disk storage separated by a space.  Given this list 
of hosts and disks, distribute 16^n buckets onto the disks.

=head1 OPTIONS

=head2 --port | -p I<port_number>

The port number to use for each server, defaults to 9001.
You can also specify a port for each host by adding a colon
and port number, for example:

 host1:1234 /disk1

=head2 --protocol http|https

The protocol to use, either http or https.

=head1 EXAMPLES

 % clad -a testarch df -kh|grep archive | awk '{print $1 " " $7}' |  ./yars_generate_diskmap 2

=head1 SEE ALSO

L<Yars>, L<Yars::Client>

=cut

use strict;
use warnings;
use JSON::XS;
use Getopt::Long qw( GetOptions );
use Pod::Usage qw( pod2usage );
use feature 'say';

sub main {
    my $class = shift;
    local @ARGV = @_;
    my %servers;
    my $default_port = 9001;
    my $protocol = 'http';
    GetOptions(
        'port|p=i'   => \$default_port,
        'protocol=s' => \$protocol,
        'help|h'     => sub { pod2usage({ -verbose => 2}) },
        'version'    => sub {
            say 'Yars version ', ($Yars::Command::yars_generate_diskmap::VERSION // 'dev');
            exit 1;
        },
    ) || pod2usage(1);
    my $digits = shift @ARGV or die "no number of digits given";
    my @all;
    while (<>) {
        chomp;
        s/#.*$//;        # remove comments
        next if /^\s*$/; # skip empty lines
        my ($host,$disk) = split;
        my $port;
        $port = $1 if $host =~ s/:(\d+)$//;
        $host =~ tr/a-zA-Z0-9.\-//dc;
        $host = join ':', $host, $port if $port;
        die "could not parse line : \"$_\"" unless $host && $disk;
        $servers{$host}{$disk} = [];
        push @all, $servers{$host}{$disk};
    }

    my $i = 0;
    for my $bucket (0..16**$digits-1) {
        my $b = sprintf( '%0'.$digits.'x',$bucket);
        push @{ $all[$i] }, "$b";
        $i++;
        $i = 0 if $i==@all;
    }

    say '---';
    say 'servers :';
    for my $host (sort keys %servers) {
        say "- url : $protocol://" . ($host =~ /:\d+$/ ? $host : join(':', $host, $default_port));
        say "  disks :";
        for my $root (sort keys %{ $servers{$host} }) {
            say "  - root : $root";
            print "    buckets : [";
            my $i = 1;
            for my $bucket (@{ $servers{$host}{$root} }) {
                print "\n               " if $i++%14 == 0;
                print " $bucket";
                print "," unless $i==@{ $servers{$host}{$root} }+1;
            }
            say " ]";
        }
    }
}

sub dense {
    my %servers = @_;
    # Alternative unreadable representation
    my @conf;
    for my $host (sort keys %servers) {
        push @conf, +{ url => "http://$host:9001", disks => [
            map +{ root => $_, buckets => $servers{$host}{$_} }, keys %{ $servers{$host} }
        ]};
    }

    my $out = JSON::XS->new->space_after->encode({ servers => \@conf });
    $out =~ s/{/\n{/g;
    $out =~ s/\[/\n[/g;
    $out =~ s/\],/],\n/g;
    print $out,"\n";
}

1;

