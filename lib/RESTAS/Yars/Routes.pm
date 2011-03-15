package RESTAS::Yars::Routes;

=head1 NAME

RESTAS::Yars::Routes -- set up the routes for RESTAS::Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for RESTAS::Yars.

=cut

use strict;
use warnings;
use Clustericious::RouteBuilder;
use Mojo::Asset::File;
use Mojo::ByteStream qw/b/;
use Log::Log4perl qw/:easy/;
use YAML::XS qw/LoadFile/;
use File::Path qw/mkpath/;
use File::Temp;

# Workaround here.  Had some namespace issues using Clustericious::Config
# because the code is not in RESTAS.pm
my $config   = LoadFile("$ENV{CLUSTERICIOUS_CONF_DIR}/RESTAS.conf");
my $data_dir = $config->{data_dir};

sub _dir {

    # Calculate the location of a file on disk.

    my $digest = shift;
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $data_dir, @clumps;
}

get '/' => sub { shift->render_text("welcome to RESTAS::Yars") };

get '/file/:filename/:md5' => sub {

    # get a file

    my $c        = shift;
    my $filename = $c->stash('filename');
    my $digest   = $c->stash('md5');

    my $dir      = _dir($digest);
    my $filepath = "$dir/$filename";

    if ( -r $filepath ) {
        my $asset = Mojo::Asset::File->new( path => $filepath );
        my $content = $asset->slurp;
        $c->render_text($content);
    }
    else {
        $c->stash( 'message' => "Not found" );
        $c->res->code('404');
        $c->render('not_found');
    }
};

any [qw/put/] => '/file/:filename' => sub {

    # put a file

    my $c        = shift;
    my $filename = $c->stash('filename');
    my $content  = $c->req->body;

    my $asset  = Mojo::Asset::File->new;
    my $digest = b( $asset->add_chunk($content)->slurp )->md5_sum->to_string;
    my $dir    = _dir($digest);
    mkpath $dir;

    my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir );
    print $tmp $content;
    $tmp->close;
    rename "$tmp", "$dir/$filename" or die "rename failed: $!";

    my $location = $c->url_for('index')->to_abs . "file/$filename/$digest";
    $c->res->code(201);    # CREATED
    $c->res->headers->location($location);
    $c->rendered;

};

any [qw/delete/] => '/file/:filename/:md5' => sub {

    # delete a file

    my $c        = shift;
    my $filename = $c->stash('filename');
    my $digest   = $c->stash('md5');
    my $dir      = _dir($digest);

    my $filepath = "$dir/$filename";
    TRACE "filepath: $filepath";

    if ( !-e $filepath ) {
        $c->res->code(404);    # NOT FOUND
        $c->rendered;
    }

    my $rv = unlink $filepath;
    if ($rv) {
        $c->res->code(200);    # OK
    }
    else {
        $c->res->code(500);    # ERROR
    }
    $c->rendered;
};

1;
