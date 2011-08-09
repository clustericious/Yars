=head1 NAME

Yars::Balancer

=head1 DESCRIPTION

1. Locally move any files that are on the wrong disk.
2. Send away any files that should not be on this host.

=head1 TODO

Improve the algorithm to handle buckets with more than
two digits.  Maybe use File::Find or Tree::Trie.

=cut

package Yars::Balancer;
use Mojo::Base qw/-base/;
use List::Util qw/max/;
use Log::Log4perl qw/:easy/;
use Mojo::IOLoop;
use File::Find qw/find/;
use Try::Tiny;
use File::Path qw/mkpath/;
use Fcntl qw(:flock);
use File::Copy qw/move/;

has 'app';

my $file_being_moved;
my $md5_being_moved;
# Move one file at time.
# This could be per (worker) process if
# we add a check for flock in wanted().
# But would the balancer then affect
# peformance of the web server?

sub _tidy_stashed_files {
    my $disk = shift;
    return if $file_being_moved;
    my @belong = @{ $disk->{buckets} };
    DEBUG "Checking disk ".$disk->{root};
    DEBUG "belong : @belong";

    # Find the first file that doesn't belong here.
    try {
        local $SIG{__DIE__};
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    my $dir = $File::Find::dir;
                    $dir =~ s/$disk->{root}//;
                    $dir =~ s[/][]g;
                    if (grep { $dir =~ /^$_/i } @belong) {
                        $File::Find::prune = 1;
                        return;
                    }
                    return unless -f;
                    TRACE "Found first hit $_";
                    $file_being_moved = $_;
                    $md5_being_moved = $dir;
                    die "found\n";
                  }
            },
            $disk->{root}
        );
    } catch {
        $file_being_moved = '' unless $_ eq "found\n";
    };
    return unless $file_being_moved;
    DEBUG "Ready to move $file_being_moved ($md5_being_moved)";

    open my $fh, ">> $file_being_moved" or do {
        TRACE "Cannot open $file_being_moved";
        return;
    };
    flock($fh, LOCK_EX | LOCK_NB ) or do {
        TRACE "Not handling $file_being_moved since it is flocked";
        close $fh;
        return;
    };
    if (my $destination_disk = Yars::Routes::disk_for($md5_being_moved)) {
        my $destination_dir = Yars::Routes::storage_path($md5_being_moved, $destination_disk);
        LOGDIE "internal error, already on $destination_disk " if $file_being_moved =~ /^$destination_disk/;
        Mojo::IOLoop->timer( 0 => sub {
            TRACE "Moving $file_being_moved to $destination_disk";
            my $failed;
            try {
                mkpath $destination_dir;
                move $file_being_moved, "$destination_dir" or die $!;
            } catch {
                ERROR "Could not move $file_being_moved to $destination_dir : $_";
                -f "$destination_dir/$file_being_moved" and unlink "$destination_dir/$file_being_moved";
                -d $destination_dir and cleanup_tree($destination_dir);
                flock $fh, LOCK_UN;
                $failed = 1;
            };
            DEBUG "Moved file $file_being_moved to $destination_dir" unless $failed;
            undef $file_being_moved;
            undef $md5_being_moved;
            return if $failed;
        });
    }
}

sub _balance {
    my $config = shift;
    DEBUG "Checking for stashed files (".time.")\n";
    my @disks = map @{ $_->{disks} }, $config->servers;
    _tidy_stashed_files($_) for @disks;
}

sub init_and_start {
    my $self = shift;
    my $config = $self->app->config;
    my $balance_delay = $config->balance_delay(default => 60*10);
    my $ioloop = Mojo::IOLoop->singleton;
    $ioloop->recurring($balance_delay => sub {  _balance($config) });
}

1;


