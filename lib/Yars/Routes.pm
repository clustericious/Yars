package Yars::Routes;

=head1 NAME

Yars::Routes -- set up the routes for Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for Yars.

=cut

use strict;
use warnings;
use Mojo::ByteStream qw/b/;
use Log::Log4perl qw/:easy/;
use File::Path qw/mkpath/;
use File::Temp;
use Clustericious::RouteBuilder;
use Clustericious::Config;

# max downloads of 1 GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

our $DataDir;
$DataDir = File::Temp->newdir( UNLINK => 1 ) if $ENV{HARNESS_ACTIVE};

ladder sub { $DataDir ||= shift->config->data_dir; };

# Calculate the location of a file on disk.
sub _dir {
    my $digest = shift;
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $DataDir, @clumps;
}

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
get '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
sub _get {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash("filename");
    return $c->render_not_found unless -r "$dir/$filename";
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
};

any [qw/put/] => '/file/(.filename)/:md5' => { md5 => 'none' } => sub {

    # put a file

    my $c        = shift;
    my $filename = $c->stash('filename');

    my $content  = $c->req->body;
    my $digest = b($content)->md5_sum->to_string;
    TRACE "md5: $digest";

    # return an error if a digest doesn't match the content
    if ( $c->stash('md5') ne 'none' and $digest ne $c->stash('md5') ) {
        $c->res->code(400);    # RC_BAD_REQUEST
        $c->res->message('incorrect digest');
        $c->rendered;
        return;
    }

    my $dir = _dir($digest);
    mkpath $dir;

    # use a temp file for atomicity
    my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir );
    print $tmp $content;
    $tmp->close;
    rename "$tmp", "$dir/$filename" or die "rename failed: $!";

    # send the URL back in the header
    my $location = $c->url_for('index')->to_abs . "file/$digest/$filename";
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
        return;
    }

    my $rv = unlink $filepath;
    $rv ? $c->res->code(200) : $c->res->code(500);
    $c->rendered;
};

1;
