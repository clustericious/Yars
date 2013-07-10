package Yars::Command::yars_generate_diskmap;

# ABSTRACT: generate a mapping from servers + hosts to buckets for yars.
our $VERSION = '0.86'; # VERSION


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
    my $port = 9001;
    my $protocol = 'http';
    GetOptions(
        'port|p=i'   => \$port,
        'protocol=s' => \$protocol,
        'help|h'     => sub { pod2usage({ -verbose => 2}) },
        'version'    => sub {
            say 'ACPS::Release version ', ($ACPS::Release::VERSION // 'dev');
            exit 1;
        },
    ) || pod2usage(1);
    my $digits = shift @ARGV or die "no number of digits given";
    my @all;
    while (<>) {
        chomp;
        my ($host,$disk) = split;
        $host =~ tr/a-zA-Z0-9._//dc;
        die "could not parse line : $_" unless $host && $disk;
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
        say "- url : $protocol://$host:$port";
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


__END__
=pod

=head1 NAME

Yars::Command::yars_generate_diskmap - generate a mapping from servers + hosts to buckets for yars.

=head1 VERSION

version 0.86

=head1 DESCRIPTION

This module contains the machinery for the command line program
L<yars_generate_diskmap>.

=head1 SEE ALSO

L<yars_generate_diskmap>

=head1 AUTHOR

original author: Marty Brandon

current maintainer: Graham Ollis <plicease@cpan.org>

contributors:

Brian Duggan

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by NASA GSFC.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

