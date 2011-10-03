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
use File::Path qw/mkpath/;
use Mojo::Base 'Mojo::Content::Single';
has 'faster_tmpdir' => sub { undef; };

sub parse {
    my $self = shift;

    # If an md5 is sent in the headers, use that to set the tempdir.

    return $self->SUPER::parse(@_) unless $self->is_parsing_body;
    return $self->SUPER::parse(@_) if $self->asset->isa("Mojo::Asset::File");
    my $md5 = $self->headers->header("Content-MD5") or return $self->SUPER::parse(@_);

    unless ($self->faster_tmpdir) {
        my $disk = Yars::Tools->disk_for($md5) or return $self->SUPER::parse(@_);
        my $faster = join '/', $disk, 'tmp';
        eval { -d $faster or mkpath $faster };
        $self->faster_tmpdir($faster) if $faster && -d $faster;
    }
    return $self->SUPER::parse(@_) unless $self->faster_tmpdir;

    my $tmp = $ENV{MOJO_TMPDIR};
    $ENV{MOJO_TMPDIR} = $self->faster_tmpdir;
    my $ok = $self->SUPER::parse(@_);
    $ENV{MOJO_TMPDIR} = $tmp;
    return $ok;
}

package Yars;

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
