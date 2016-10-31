package Yars::Command::yars_balance;

use strict;
use warnings;
use 5.010;
use Yars;
use Yars::Client;
use Path::Class qw( dir );
use Getopt::Long qw( GetOptions );
use Pod::Usage qw( pod2usage );

# PODNAME: yars_balance
# ABSTRACT: Fix all files
# VERSION

=head1 SYNOPSIS

 % yars_balance

=head1 DESCRIPTION

Possible future replacement for L<yars_fast_balance>.

=cut

sub _recurse 
{
  my($root, $cb) = @_;
  foreach my $child ($root->children)
  {
    if($child->is_dir)
    {
      _recurse($child,$cb);
    }
    else
    {
      $cb->($child);
    }
  }
  
  my $count = do {
    use autodie;
    my $dh;
    opendir $dh, $root;
    my $count = scalar grep !/^\.\.?$/, readdir $dh;
    closedir $dh;
    $count;
  };
  
  if($count == 0)
  {
    rmdir $root;
  }
}

sub main
{
  local @_ = @ARGV;
  GetOptions(
    'help|h' => sub { pod2usage({ -verbose => 2 }) },
    'version' => sub {
      say 'Yars version ', ($Yars::Command::yars_fast_balance::VERSION // 'dev');
      exit 1;
    },
  ) || pod2usage(1);
  
  my $yars = Yars->new;
  my $client = Yars::Client->new;

  do {
    # doublecheck that the local bucket map and the
    # server bucketmap match.  Otherwise we could
    # migrate a file to the same server, and then
    # delete it, thus loosing the file!  Not good.
    my $my_bucket_map = $yars->tools->bucket_map;
    my $server_bucket_map = $client->bucket_map;
    
    foreach my $key (keys %$my_bucket_map)
    {
      if($my_bucket_map->{$key} ne delete $server_bucket_map->{$key})
      {
        die "client/server mismatch on bucket $key";
      }
    }
    foreach my $key (keys %$server_bucket_map)
    {
      die "client/server mismatch on bucket $key";
    }
  };

  foreach my $server ($yars->config->servers)
  {
    # only rebalance disks that we are responsible for...
    # even if perhaps those disks are available to us...
    next unless $yars->config->url eq $server->{url};
    foreach my $disk (@{ $server->{disks} })
    {
      my $root = dir( $disk->{root} );
      foreach my $dir (sort grep { $_->basename =~ /^[a-f0-9]{1,2}$/ } $root->children)
      {
        my $expected = $yars->tools->disk_for($dir->basename);
        next if defined($expected) && $expected eq $dir->parent; 
        _recurse $dir, sub {
          my($file) = @_;
          say $file->basename;
          $client->upload('--nostash' => 1, "$file") or do {
            warn "unable to upload $file @{[ $client->errorstring ]}";
            return;
          };
          
          # we did a bucket map check above, but doublecheck the header returned
          # to us for the server doesn't match the old server location.  If
          # there is a server restart between the original check and here it
          # could otherwise cause problems.
          my $new_location = Mojo::URL->new($client->res->headers->location);
          my $old_location = Mojo::URL->new($yars->config->url);
          $old_location->path($new_location->path);
          if("$new_location" eq "$old_location")
          {
            die "uploaded to the same server, probably configuration mismatch!";
          }
          
          unlink "$file" or do {
            warn "unable to unlink $file $!";
            return;
          };
        };
      }
    }
  }
}

1;
