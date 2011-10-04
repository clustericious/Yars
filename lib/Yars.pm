package Yars;

=head1 NAME

Yars (Yet Another REST Server)

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
use Yars::Balancer;
use Yars::Message::Request;
use Yars::Content::Single;
our $VERSION = '0.41';

__PACKAGE__->attr( secret => rand );

sub startup {
    my $self = shift;
    $self->SUPER::startup(@_);
    $self->hook(after_build_tx => sub {
        my ($tx,$app) = @_;
        my $req = Yars::Message::Request->new();
        $tx->req($req);
    });
}

1;
