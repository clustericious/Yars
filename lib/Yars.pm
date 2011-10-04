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
use Clustericious::Log;
use File::Path qw/mkpath/;
use Mojo::Base 'Mojo::Content::Single';
has 'content_disk' => sub { undef; };

sub parse {
    my $self = shift;

    # If an md5 is sent in the headers, use that to set the tempdir.

    return $self->SUPER::parse(@_) unless $self->is_parsing_body;
    return $self->SUPER::parse(@_) if $self->asset->isa("Mojo::Asset::File");
    my $md5 = $self->headers->header("Content-MD5") or return $self->SUPER::parse(@_);

    my $disk;
    unless ($disk = $self->content_disk) {
        $disk = Yars::Tools->disk_for($md5) || '/dev/null'; # (/dev/null == not ours)
        $self->content_disk($disk);
    }
    return $self->SUPER::parse(@_) if $self->content_disk eq '/dev/null';
    return $self->SUPER::parse(@_) unless Yars::Tools->disk_is_up($disk);
    my $tmpdir = join '/', $disk, 'tmp';
    eval { -d $tmpdir or mkpath $tmpdir };
    if ($@ or ! -d $tmpdir) {
        WARN "Cannot make tmpdir $tmpdir ".($@ || '');
        return $self->SUPER::parse(@_);
    }

    my $tmp = $ENV{MOJO_TMPDIR};
    $ENV{MOJO_TMPDIR} = $tmpdir;
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
