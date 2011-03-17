package Yars::Routes;

=head1 NAME

Yars::Routes -- set up the routes for Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for Yars.

=cut

use strict;
use warnings;
use Clustericious::RouteBuilder;
use Clustericious::Config;
use Mojo::Asset::File;
use Mojo::ByteStream qw/b/;
use Log::Log4perl qw/:easy/;
use YAML::XS qw/LoadFile/;
use File::Path qw/mkpath/;
use File::Temp;

my $data_dir;
if ( $ENV{HARNESS_ACTIVE} ) {
    $data_dir = File::Temp->newdir( UNLINK => 1 );
}
else {
    $data_dir = Clustericious::Config->new('Yars')->data_dir;
}


sub _dir {

    # Calculate the location of a file on disk.

    my $digest = shift;
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $data_dir, @clumps;
}

get '/' => sub { shift->render_text("welcome to Yars") };

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

any [qw/put/] => '/file/:filename/:md5' => {md5 => 'none'} => sub {

    # put a file 

    my $c        = shift;
    my $filename = $c->stash('filename');

    my $content  = $c->req->body;

    my $asset  = Mojo::Asset::File->new;
    my $digest = b( $asset->add_chunk($content)->slurp )->md5_sum->to_string;

    if ( $c->stash('md5') ne 'none' and $digest ne $c->stash('md5') ) {
        $c->res->code(400);  # RC_BAD_REQUEST
        $c->rendered;
        return;
    }


    my $dir    = _dir($digest);
    mkpath $dir;

    # use a temp file for atomicity
    my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir );
    print $tmp $content;
    $tmp->close;
    rename "$tmp", "$dir/$filename" or die "rename failed: $!";

    # send the URL back in the header
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
