=head1 NAME

Yars::Message::Request -- an incoming request

=head1 DESCRIPTION

Just like Mojo::Message::Request, but uses
Yars::Content::Single for the content.

=cut

package Yars::Message::Request;
use Yars::Content::Single;
use Mojo::Base 'Mojo::Message::Request';
has content => sub { Yars::Content::Single->new() };

1;

