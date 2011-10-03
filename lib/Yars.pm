package Yars;

=head1 NAME

Yars (Yet Another REST Server)

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
use Yars::Balancer;
our $VERSION = '0.41';

__PACKAGE__->attr( secret => rand );

package Yars::Message::Request;
use Mojo::Base 'Mojo::Message::Request';
has content => sub { Yars::Content::Single->new() };

package Yars::Content::Single;
use Mojo::Base 'Mojo::Content::Single';
sub parse {
    $ENV{MOJO_TMPDIR} = "/tmp";
    shift->SUPER::parse(@_);
}

package Yars;

sub startup {
    my $self = shift;
    $self->SUPER::startup(@_);
    $self->hook(after_build_tx => sub {
        my ($tx,$app) = @_;
        $tx->req(Yars::Message::Request->new());
    });
    1;
}

1;
