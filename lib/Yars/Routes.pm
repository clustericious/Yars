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
use Digest::MD5 qw(md5_hex);
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

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get '/file/(.filename)/:md5' => sub {

    # get a file

    my $c        = shift;
    my $filename = $c->stash('filename');
    my $digest   = $c->stash('md5');

    my $dir      = _dir($digest);
    my $filepath = "$dir/$filename";

    # return not_found if the file doesn't exist
    unless ( -r $filepath ) {
        $c->stash( 'message' => "Not found" );
        $c->res->code('404');
        $c->render('not_found');
    }


    my $asset = Mojo::Asset::File->new( path => $filepath );
    my $content = $asset->slurp;
    if ( -B $filepath ) {
        # a binary file
        TRACE "sending a binary file";
        $c->res->code(200); 
        $c->res->fix_headers;
        $c->stash->{'mojo.rendered'} = 1;
        my $bi_content = Mojo::ByteStream->new($content);
        $c->res->body($bi_content);
        $c->rendered;
    }
    else {
        # a text file
        TRACE "sending a text file";
        $c->render_text($content);
    }
};

any [qw/put/] => '/file/(.filename)/:md5' => {md5 => 'none'} => sub {

    # put a file 

    my $c        = shift;
    my $filename = $c->stash('filename');

    my $content  = $c->req->body;
    my $digest = md5_hex($content);
    TRACE "md5: $digest";

    # return an error if a digest doesn't match the content
    if ( $c->stash('md5') ne 'none' and $digest ne $c->stash('md5') ) {
        $c->res->code(400);  # RC_BAD_REQUEST
        $c->res->message('incorrect digest');
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

any [qw/delete/] => '/file/(.filename)/:md5' => sub {

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
