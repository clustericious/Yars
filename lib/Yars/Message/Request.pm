package Yars::Message::Request;
use Yars::Content::Single;
use Mojo::Base 'Mojo::Message::Request';
has content => sub { Yars::Content::Single->new() };

1;

