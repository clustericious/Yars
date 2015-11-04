package Yars::Command::yars_exercise;

# PODNAME: yars_exercise
# ABSTRACT: Exercise a Yars server from the client side
BEGIN {
# VERSION
}

=head1 SYNOPSIS

 $ yars_exercise --version -h|--help -m|--man

 $ yars_exercise -v|--verbose -q|--quiet [...other log options]

 $ yars_exercise --numclients 4 --files 20 --size 8KiB --gets 10
                 --temppath /tmp

 $ yars_exercise -n 4 -f 20 -s 8KiB -g 10 -t /tmp

 $ yars_exercise [with no options, uses the defaults above]

 $ yars_exercise -runs runs_desc.txt

=head1 DESCRIPTION

Forks <numclients>.  Each client first creates <files> files of size
<size> filled with random bytes, Then it PUTs them to Yars, GETs them
<gets> times, then DELETEs.

For each client, it randomly shuffles the order of PUTs, GETs, and
DELETEs, so it may PUT 1 file, PUT another, GET the first, PUT a
third, GET the second, DELETE the first, etc.  The only guarantee is
that for each individual file, the first action on that file is a PUT,
the last is a DELETE.  With multiple clients, this causes GETs/PUTs to
intermingle.

All actions are performed through Yars::Client -- it uses the
upload(), download() and remove() methods.

size and chunksize can be specified with K, KB, KiB, M, MB, MiB, etc.

chunksize is only used for creating the temp files, changing it won't
affect the Yars actions.

You can also put your config options in a YAML file and specify it
with "--runs" or "-r":

 $ cat runs_desc.txt
   clients: [2,4]
   files: [5,10]
   gets: [10,20,40,80]
   size: [256,256K,8M]

If you list more than one option, it iterates through various
parameters listed.

--runs also outputs CSV of stats from each run.

Use "-q" or "--quiet" option to supress INFO log messages, or
yars_exercise -runs runs_desc.txt | tee stats.csv

If you are really brave, you can specify STDIN with filename '-'

 $ yars_exercise -r - | tee stats.csv
 clients: [2,4]
 files: [5,10]
 gets: [10,20,40,80]
 size: [256,256K,8M]

=head1 LOGGING

Uses Log::Log4perl and Log::Log4perl::CommandLine, so you can specify
any logging options they support, e.g. "--debug root" will log a note
with the elapsed time for each action, "--trace Yars::Client" will log
detailed trace log messages from the client, etc.

=cut

use strict;
use warnings;
use 5.010;
use Log::Log4perl qw(:easy);
use Log::Log4perl::CommandLine ':all', ':loginit' => { level => $INFO };
use Pod::Usage::CommandLine qw(GetOptions pod2usage);
use Yars::Client;
use Number::Bytes::Human qw(format_bytes parse_bytes);
use Parallel::ForkManager;
use Path::Tiny;
use Digest::MD5;
use List::Util qw(shuffle);
use Time::HiRes qw(gettimeofday tv_interval);
use YAML::XS qw(LoadFile);

my $chunksize;
my $temppath;

main(@ARGV) unless caller;

sub main
{
    local @ARGV = @_;

    GetOptions(
        'numclients:i' => \(my $clients = 4),        # if you change defaults
        'files:i'      => \(my $numfiles = 20),      # update SYNOPSIS
        'size:s'       => \(my $human_size = '8KiB'),
        'gets:i'       => \(my $gets = 10),
        'runs:s'       => \(my $runsfilename),
        'chunksize:s'  => \(my $human_chunksize = '8KiB'),
        'temppath:s'   => \($temppath = '/tmp')
    ) or pod2usage;

    $chunksize = parse_bytes($human_chunksize);

    exit multiruns($runsfilename) if $runsfilename;

    my $size = parse_bytes($human_size);
    $human_size = format_bytes($size);

    my $totalfiles = $clients * $numfiles;

    INFO "Create $totalfiles files, each about $human_size bytes.";
    INFO "PUT each file to Yars, then GET $gets times, then DELETE.";
    INFO "$clients clients will work in parallel on $numfiles each.";

    my ($times, $ret) = exercise($clients, $numfiles, $size, $gets);

    say "PUT avg time    ", $times->{PUT};
    say "GET avg time    ", $times->{GET};
    say "DELETE avg time ", $times->{DELETE};

    foreach my $method (qw(PUT GET DELETE))
    {
        say "$method $_ ", $ret->{$method}{$_} foreach keys %{$ret->{$method}};
    }
}

sub multiruns
{
    my ($runsfilename) = @_;

    my $runsdesc = LoadFile($runsfilename);

    foreach my $field (qw(clients files size gets))
    {
        if (not defined $runsdesc->{$field}
            or ref $runsdesc->{$field} ne 'ARRAY')
        {
            LOGDIE "Poorly formatted runs description file $field";
        }
    }

    say "clients,files,gets,size,PUT avg time,GET avg time,DELETE avg time,",
        "PUTs,GETs,DELETEs";

    foreach my $clients (@{ $runsdesc->{clients} })
    {
        foreach my $files (@{ $runsdesc->{files} })
        {
            foreach my $gets (@{ $runsdesc->{gets} })
            {
                foreach my $size (map {parse_bytes $_} @{ $runsdesc->{size} })
                {
                    INFO "Starting clients=$clients, files=$files, ",
                         "gets=$gets, size=$size";

                    my ($times, $ret) = exercise($clients, $files,
                                                 $size, $gets);

                    say join ',', $clients, $files, $gets, $size,
                        $times->{PUT}, $times->{GET}, $times->{DELETE},
                        $ret->{PUT}{ok}, $ret->{GET}{ok}, $ret->{DELETE}{1};

                    if ($ret->{PUT}{ok} != $clients*$files)
                    {
                        ERROR "Failed PUTs";
                    }
                    if ($ret->{GET}{ok} != $clients*$files*$gets)
                    {
                        ERROR "Failed GETs";
                    }
                    if ($ret->{DELETE}{1} != $clients*$files)
                    {
                        ERROR "Failed DELETEs";
                    }
                }
            }
        }
    }

    return 0;
}

sub exercise
{
    my ($clients, $numfiles, $size, $gets) = @_;

    my $pm = Parallel::ForkManager->new($clients)
        or LOGDIE;

    my @client_stats;

    $pm->run_on_finish(sub {
        my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $stats) = @_;
        push @client_stats, $stats;
    });

    CLIENT:
    for (my $i = 0; $i < $clients; $i++)
    {
        $pm->start and next CLIENT;
        $pm->finish(0, exercise_worker($i, $numfiles, $size, $gets));
    }

    $pm->wait_all_children;

    my (%times, %ret);

    foreach my $stat (@client_stats)
    {
        foreach my $method (qw(PUT GET DELETE))
        {
            $times{$method} += $stat->{times}{$method};

            $ret{$method}{$_} += $stat->{ret}{$method}{$_}
                foreach keys %{$stat->{ret}{$method}};
        }
    }
    $times{PUT}    /= $clients*$numfiles;
    $times{GET}    /= $clients*$numfiles*$gets;
    $times{DELETE} /= $clients*$numfiles;

    return \%times, \%ret;
}

sub exercise_worker
{
    my ($clientno, $numfiles, $size, $gets) = @_;

    srand(($clientno+1) * gettimeofday);

    my @filelist;

    for (my $i = 0; $i < $numfiles; $i++)
    {
        my $newfile = make_temp_file($size);
        for (my $j = 0; $j < $gets+2; $j++)
        {
            push @filelist, { %$newfile };
        }
    }

    my %count;
    my %times;
    my %ret;

    my $yc = Yars::Client->new;

    foreach my $file (shuffle @filelist)
    {
        my $instance = ++$count{$file->{filename}};

        my $path = "/file/$file->{filename}/$file->{md5}";

        my $t0 = [gettimeofday];

        my ($ret, $method);

        if ($instance == 1)
        {
            $method = 'PUT';
            DEBUG "PUT $path";
            $ret = $yc->upload($file->{filepath});
        }
        elsif ($instance == $gets+2)
        {
            $method = 'DELETE';
            DEBUG "DELETE $path";
            $ret = $yc->remove($file->{filename}, $file->{md5});
        }
        else
        {
            $method = 'GET';
            DEBUG "GET $path";
            $ret = $yc->download($file->{filename}, $file->{md5}, $temppath);
        }
        my $elapsed = tv_interval($t0);
        $times{$method} += $elapsed;

        unlink $file->{filepath};

        $ret //= 'undef';
        $ret{$method}{$ret}++;

        DEBUG "DONE $ret $elapsed";
    }

    return { times => \%times, ret => \%ret };
}
    
sub make_temp_file
{
    my ($filesize) = @_;

    my $newfile = Path::Tiny->tempfile(UNLINK => 0,
                                       TEMPLATE => 'yarsXXXXX',
                                       DIR => $temppath)
        or LOGDIE "Can't make temp file";

    DEBUG "Creating $newfile";

    my $md5 = Digest::MD5->new;

    for (; $filesize > 0; $filesize -= $chunksize)
    {
        my $chunk = random_bytes($filesize > $chunksize
                                 ? $chunksize : $filesize);

        $md5->add($chunk);

        $newfile->append_raw($chunk)
            or LOGDIE "Failed writing to $newfile";
    }

    return { filename => $newfile->basename, 
             filepath => $newfile->stringify,
             md5 => $md5->hexdigest };
}

sub random_bytes
{
    my $number = shift;
    return '' unless $number > 0;
    pack("C$number", map { int(rand()*256) } 0..$number);
}

1;
