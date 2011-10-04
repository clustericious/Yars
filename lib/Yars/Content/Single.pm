=head1 NAME

Yars::Content::Single - incoming content

=head1 DESCRIPTION

Just like Mojo::Content::Single, but uses a tempdir
that is in the right directory.

=over

=cut

package Yars::Content::Single;
use Clustericious::Log;
use File::Path qw/mkpath/;
use Mojo::Base 'Mojo::Content::Single';

has 'content_disk' => sub { undef; };

=item parse

Parse the incoming request.  Just
falls through except for the case
where we need to determine the disk
and the temp directory for the file.

=cut

sub parse {
    my $self = shift;

    # If an md5 is sent in the headers, use that to set the tempdir.

    return $self->SUPER::parse(@_) unless $self->is_parsing_body;
    return $self->SUPER::parse(@_) if $self->asset->isa("Mojo::Asset::File");
    my $md5 = $self->headers->header("Content-MD5") or do {
        TRACE "No md5 in headers";
        return $self->SUPER::parse(@_);
    };

    my $disk;
    unless ($disk = $self->content_disk) {
        Yars::Tools->refresh_config;
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
    TRACE "Set tmpdir to $tmpdir, calling SUPER::parse";
    my $ok = $self->SUPER::parse(@_);
    $ENV{MOJO_TMPDIR} = $tmp;
    return $ok;
}

1;

