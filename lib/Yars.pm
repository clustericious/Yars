package Yars;

=head1 NAME

Yars (Yet Another REST Server)

=over

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
use Yars::Tools;
use Mojo::ByteStream qw/b/;
use File::Path qw/mkpath/;
our $VERSION = '0.72';

__PACKAGE__->attr( secret => rand );

=item startup

Called by the server to start up, we change
the object classes to use Yars::Message::Request
for incoming requests.

=cut

sub startup {
    my $self = shift;
    if ($Mojolicious::VERSION >= 2.37) {
        Mojo::IOLoop::Stream->timeout(3000);
    } else {
        Mojo::IOLoop->singleton->connection_timeout(3000);
    }
    $self->hook(
        after_build_tx => sub {
            my ( $tx, $app ) = @_;
            $tx->req->content->on(body => sub {
                    my $content = shift;
                    my $md5_b64 = $content->headers->header('Content-MD5') or return;
                    my $md5 = unpack 'H*', b($md5_b64)->b64_decode;
                    my $disk = Yars::Tools->disk_for($md5) or return;
                    my $tmpdir = join '/', $disk, 'tmp';
                    -d $tmpdir or do { mkpath $tmpdir;  chmod 0777, $tmpdir; };
                    -w $tmpdir or chmod 0777, $tmpdir;
                    $content->asset->on(
                        upgrade => sub {
                            my ( $mem, $file ) = @_;
                            $file->tmpdir($tmpdir);
                        }
                    );
                }
            );
        }
    );
    $self->SUPER::startup(@_);
}

1;
