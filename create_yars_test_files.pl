#!/usr/local/bin/perl -w

use strict;
use Cwd;
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
use Parallel::ForkManager;
use Getopt::Long;
use Yars::Client;

$| = 1;
my $debug = 1;

chomp(my $time_stamp = `date +%s`);
my $errata_file = "errata_create_file_" . $time_stamp . ".txt";
open( E, ">", $errata_file) or die "unable to open file $errata_file  for writing $!\n";

chomp(my $current_dir  = `pwd`);
chdir($current_dir);
my $file_data_source = "FILES/file_creation_help_file.txt";
open(R, "<", $file_data_source) or die "unable to open file $file_data_source for reading $! \n";

my $absolute_proc_limit = 500;
my $index = 0;
my $ppid = $$;
my $active_procs = 1;
my %helper_hash;
my $recovery_directory = "$ENV{HOME}/tmp2";

chomp( my $hostname = `hostname`);

while(<R>){
  chomp( my $line = $_ );
  my @all = split / /, $line;
  $helper_hash{$index}{'working_name'} = $all[0];
  $helper_hash{$index}{'md5sum'} = $all[1];
  $helper_hash{$index}{'length'} = $all[2];
  $helper_hash{$index}{'original_name'} = $all[3];
  $helper_hash{$index}{'in_use'} = 0;
  $index++;
}
close(R);

my $file_count_target = 10;
my $max_procs = 2;
my $statistic_hash = {};
my $last_entry = $index - 1;

my $result = GetOptions(   "count|files|f=i" => \$file_count_target,
                           "procs|processes|p=i" => \$max_procs,
                       );

if ( $file_count_target > 1000000){
  print E "setting file_count_target to 1000000\n";
  $file_count_target = 1000000;
} elsif  ( $file_count_target < 0){
  print E "setting file_count_target to 1\n";
  $file_count_target = 1;
}

if ( $max_procs > $absolute_proc_limit){
  print E "resetting max_procs to $absolute_proc_limit\n";
  $max_procs = $absolute_proc_limit;
} elsif  ( $max_procs < 0){
  print E "resetting max_procs to 1\n";
  $max_procs = 1;
}



print E "after getopts \$max_procs = $max_procs and \$file_count_target = $file_count_target\n";

print E "\$last_entry is $last_entry\n";

my $log_file = "statistics_for_yars_WRITE_files_" . $file_count_target . "_files_" . $max_procs . "_processes_"  . $time_stamp . ".txt";
open( L, ">", $log_file) or die "unable to open file $log_file for writing $!\n";
print L "Process ID, filename , number of bytes, total test time, mkdir time, copy time, copy rate\n"; 
my $read_test_file = "journal_of_written_files_" .  $time_stamp  . ".txt";
open(J, ">" , $read_test_file ) or die "unable to open file $read_test_file for writing $! \n"; 
#print E Dumper(\%helper_hash);

my $source_test_file_path = $current_dir . "/"  . "FILES";
print E "\$source_test_file_path is $source_test_file_path \n"; 
if ( ! -e $source_test_file_path){
  mkdir($source_test_file_path) or die "unable to make directory $source_test_file_path\n";
}

sub get_microseconds_now {
    my ( $seconds, $microseconds ) = gettimeofday();
    my ($all_microseconds);
    $all_microseconds = ( $seconds * 10**6 ) + $microseconds;
    return $all_microseconds;
}

my $rand = int(rand(100000000));
my $grand_start_time = get_microseconds_now;

my $temp_dir = "/home/phiggins/tmp";
if ( ! -e $temp_dir){
  mkdir ($temp_dir) or die "unable to make directory $temp_dir $!\n";
}
my $fm =  new Parallel::ForkManager($max_procs, "/home/phiggins/tmp");


$fm->run_on_finish ( # called BEFORE the first call to start()
    sub {
      my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_structure_reference) = @_;
      $active_procs--;
      print "active procs: $active_procs\n";
      print E "$pid in run_on_finish sub \$pid = $pid  \n" if ($debug);
      print E "$pid in run_on_finish sub \$ident = $ident \n" if ($debug);
      my $recovery_filename = "$ppid.$pid.$ident.txt";
      my $recovery_candidate  = $recovery_directory . "/" . $recovery_filename;
      
      print E "$pid in run_on_finish sub \$exit_code = $exit_code  \n" if ($debug);

      if ( $exit_code != 0 ){
        print E "$pid in run_on_finish with exit_code: $exit_code and attempting to recover\n";
        if ( -e $recovery_candidate ){
          print E "$pid recovery candidate file $recovery_candidate found\n";
          open( RC , "<", $recovery_candidate ) or die "unable to open file $recovery_candidate for reading $!\n";
          while(<RC>){
            chomp(my $text = $_);
            my $source = (split / /, $text)[1];
            my $destination = (split / /, $text)[0];
            my $return = `mv $source $destination`;
            if ($return){
              print E "$pid recovery attempt failed\n";
              last;
            }
            print E "$pid recovery successful\n";
            last;
          }
        } else {
          print E "$pid  recovery candidate file $recovery_candidate NOT FOUND recover not possible for error: $exit_code\n";
        }
        while ( -e $recovery_candidate ){
          unlink $recovery_candidate;
        }
        last;
      }

      print E "$pid in run_on_finish sub \$exit_signal = $exit_signal  \n" if ($debug);
      print E "$pid in run_on_finish sub \$core_dump = $core_dump  \n" if ($debug);
      print E "$pid in run_on_finish sub \$data_structure_reference = " . ${$data_structure_reference} . " \n" if ($debug and defined($data_structure_reference));
      # retrieve data structure from child
      if (defined($data_structure_reference)) {  # children are not forced to send anything
        my $string = ${$data_structure_reference};  # child passed a string reference
        print E "$pid run_on_finish $string\n";

#   my $statement = "$length 1 $filename $length $total_time $mkdir_time $copy_time $copy_rate";

        my @return_array = split / /,$string;

        last if ( not defined $return_array[7]);
        my $bytes = $return_array[0];
        my $filename = $return_array[2];
        my $length = $return_array[3];
        my $total_time = $return_array[4];
        my $mkdir_time = $return_array[5];
        my $copy_time = $return_array[6];
        my $copy_rate = $return_array[7];
#Swap:      4192924        100    4192824
        my $free_swap_space = 9999999999999;
        open( S , "free -l|") or die "unable to open pipe to read free command output $!\n";
          while(<S>){
          
          chomp( my $line = $_);
#         print E "line is $line\n";
          next unless ( $line =~ /Swap/);
#         print E "line is $line\n";
          $line =~ s/  */ /g;
#         print E "line is $line\n";
 
          $free_swap_space = ( split / /, $line)[1];
#         print E "free swap space is $free_swap_space\n";
        } 
        close(S);
        print L "$pid $filename $length $ident $active_procs $free_swap_space $total_time $mkdir_time $copy_time $copy_rate \n";

        print E "$pid run_on_finish return_array[0] = $return_array[0] return_array[1] = $return_array[1] $filename $total_time $mkdir_time $copy_time $copy_rate\n";
#       print E "$pid returning undef  because the return array was all zero\n" and return undef  if ( $return_array[0] == 0 && $return_array[1] == 0); 
        $statistic_hash->{"$ppid-$pid-$ident"}{'bytes'} = $return_array[0];
        $statistic_hash->{"$ppid-$pid-$ident"}{'count'} = 1;
        $ident = "NULL" unless ( defined $ident);
        print E "\$pid = $pid \$exit_code = $exit_code \$ident = $ident \$exit_signal = $exit_signal \$core_dump = $core_dump statistic_hash->bytes = " . $statistic_hash->{"$ppid-$pid-$ident"}{'bytes'} . " \n";
      } else {  # problems occuring during storage or retrieval will throw a warning
        print E qq|$pid No message received from child process \n|;
      }
      while ( -e $recovery_candidate ){
        unlink $recovery_candidate;
      }
    }
  );

$fm->run_on_start (
   sub { my ($pid,$file_number)=@_;
      print "$pid started processing test file number $file_number started, pid: $pid\n";
      $active_procs++;
    }
  );


my $file_number;
for ( $file_number = 1; $file_number <= $file_count_target; $file_number++ ) {
  my $pid = $fm->start($file_number) and next;
  my $statement =  push_file_to_archive($file_number);
  if ( not defined ( $statement)){
    print "$pid push_file_to_archive returned undef\n";
  }
  $fm->finish(0, \$statement);
}

$fm->wait_all_children;

sub push_file_to_archive{
    my $file_number = shift;
    my $working_file_number =  ($file_number % $last_entry);
    my $pid = $$;
    srand( time ^ $pid);
    $| = 1;
    my $rand = int( rand( $pid * $pid ));
#   print E "$pid \$last_entry $last_entry \$file_number $file_number modulus fn \% le " . ($file_number % $last_entry) . " \n";
#   print E "$pid in push_file_to_archive with filenumber = $file_number\n";
#   print E "$pid in push_file_to_archive \$working_file_number  = $working_file_number \$last_entry = $last_entry\n";
    srand( time ^ $pid ^ $working_file_number);


    my $base_file_path = undef;
    my $test_file_path = undef;

    srand( time ^ $pid);

    my $candidate_md5sum = undef;
    my $candidate_original_name = undef;
    my $length = undef;
    my $filename = undef;
    my $file_found = 0;
    my $attempt_count = 0;
   
    while ( ! $file_found ){
      $working_file_number = int( rand ($last_entry + 1));
  
      $candidate_md5sum = $helper_hash{$working_file_number}{'md5sum'};
      $candidate_original_name = $helper_hash{$working_file_number}{'original_name'};
      $length = $helper_hash{$working_file_number}{'length'};

      $filename = "ACPS_TEST_FILE_rand_" . $rand . "_HOST_" . $hostname . "_disk_" . "NULL" . "_process_id_" . $pid . "_file_number_" . $file_number . "_working_file_number_" . $working_file_number . "_length_" . $length . ".txt";

      print E "$pid test filename will be  $filename \n";

      my $the_choice =  "$source_test_file_path" . "/" . "$candidate_original_name"; 
#     print E "$pid the choice is $the_choice\n";

      $base_file_path = "$source_test_file_path" . "/" . "$candidate_original_name";
      $test_file_path = "$source_test_file_path" . "/" . "$filename"; 
      if ( -e $the_choice) {
#       print E "$pid \$base_file_path is $base_file_path\n";
#       print E "$pid \$test_file_path is $test_file_path\n";
       
        my $return = `mv $base_file_path  $test_file_path`;
        if ( $return){
          print E "$pid mv \$base_file_path  \$test_file_path $base_file_path  $test_file_path returned $return rather than zero\n";
          return undef;
        }
        $file_found++;
      } else {
        $attempt_count++;
        print E "$pid candidate file: $the_choice not available for filenumber: $file_number working file number: $working_file_number trying again attempt: $attempt_count\n" ;
      }      
    }
    my $recovery_file = "$ppid.$pid.$file_number.txt";
    my $recovery_path = $recovery_directory . "/" . $recovery_file;
    open (R, ">", $recovery_path ) or die "unable to open file $recovery_path for writing $!\n";
    print R "$base_file_path $test_file_path\n";
    close(R);
    print E "$pid \$test_file_path is $test_file_path in upload command md5sum of the file is $candidate_md5sum \n";

    my $starttime = get_microseconds_now();

    my $before_mkdir_time = get_microseconds_now();

    my $r = Yars::Client->new;

    my $retrys = 0;
    my $retry_limit = 10;
    my $nap = 2;
    my $after_mkdir_time = get_microseconds_now();
    print E "$pid immediately before upload command\n";
 
    $r->upload($test_file_path); ### or print E "$pid  $r->errorstring\n";
    my $return = $r->errorstring;
#   print E "$pid value of return is $return\n";
    while ($return !~ /201/  && $retrys < $retry_limit) { 
       print E "$pid in retry loop with return: $return and retrys: $retrys \n";
       sleep $nap;
       $r->upload($test_file_path); ### or print E "$pid  $r->errorstring\n";
       $return = $r->errorstring;
       print E "$pid in retry loop and after internal upload with return: $return and retrys: $retrys \n";
       $retrys++;
    }

    if (($return !~ /201/)  && ($retrys => $retry_limit)) { 
       print E "$pid ERROR upload(test_file) returned $return rather than 201 after $retrys retrys\n";
       undef $r;
       my $next_return = `mv $test_file_path $base_file_path`;
       if ( $next_return){
          print E "$pid ERROR mv \$test_file_path \$base_file_path $test_file_path $base_file_path returned $next_return rather than zero\n";
          return undef;
       }
       return undef;
    }
       
    print E "$pid immediately after upload command\n";

    print E "$pid r->res->headers->location " . $r->res->headers->location . " \n";


    my $after_copy_time = get_microseconds_now();

    undef $r;
    print J "$candidate_md5sum" . " " . "$test_file_path\n";
    my $total_time = $after_copy_time - $starttime;
    my $mkdir_time = $after_mkdir_time - $before_mkdir_time;
    my $copy_time = $after_copy_time - $after_mkdir_time;
    my $copy_rate = $length / $copy_time;
#   print L "$pid $filename $length $total_time $mkdir_time $copy_time $copy_rate\n";
    print E "$pid move command is mv $test_file_path $base_file_path\n";
    $return = `mv $test_file_path $base_file_path`;
    if ( $return){
      print E "$pid ERROR mv \$test_file_path \$base_file_path $test_file_path $base_file_path returned $return rather than zero\n";
      return undef;
    }
#   print E "$pid $filename $length $total_time $mkdir_time $copy_time $copy_rate\n";
#   print E "$pid value of return after copy  is $return\n"; 
    
    
#   print E "$pid value of md5sum is $candidate_md5sum \n";
#   print E "$pid value of file_number is $file_number \n";
    my $statement = "$length 1 $filename $length $total_time $mkdir_time $copy_time $copy_rate";
    return $statement;
}
my $stat_count;
my $stat_total;

foreach my $pid ( sort ( keys %{$statistic_hash})){
#  print E "before $pid stat count is $stat_count and stat total is $stat_total\n" if ( defined ( $stat_count ) and defined ( $stat_total ));
   $stat_count += $statistic_hash->{$pid}{'count'};
   $stat_total += $statistic_hash->{$pid}{'bytes'};
   print E "after $pid stat count is $stat_count increment was " . $statistic_hash->{$pid}{'bytes'} . " and stat total is $stat_total\n";
}

print E "after iterating through statistic_hash  stat count is $stat_count and stat total is $stat_total\n";

#print E "DUMPING \$statistic_hash\n"; 
#print E Dumper($statistic_hash); 


my $grand_stop_time = get_microseconds_now;
my $grand_elapsed_time = $grand_stop_time - $grand_start_time;
my $grand_rate = $stat_total / $grand_elapsed_time;
print L "TOTALS files $stat_count bytes $stat_total time $grand_elapsed_time rate $grand_rate\n";

close(L);
close(E);
close(J);

__END__;
1;
#!/usr/bin/env perl

use Yars::Client;
use Mojo::Asset::File;
use Mojo::ByteStream qw/b/;
use strict;

my @filenames;
my @md5s;
my $how_many = $ARGV[0] || 100;

mkdir 'files';
for (1..$how_many) {
    open my $fp, ">files/file.$_";
    print $fp "some data $_";
    print $fp 'more data' for 1..$how_many;
    close $fp;
}

print "uploading\n";
my $y = Yars::Client->new();
my @locations;
for (1..$how_many) {
    $y->upload("files/file.$_") or print $y->errorstring;
    push @locations, $y->res->headers->location;
    push @filenames, "file.$_";
    my $a =  Mojo::Asset::File->new(path => "files/file.$_");
    push @md5s,b($a->slurp)->md5_sum;
}


system ('rm -rf ./got');
mkdir 'got';
chdir 'got';

for (1..$how_many) {
    my $loc = shift @locations;
    #$y->download($loc) or print "failed to get $loc: ".$y->errorstring."\n";
    my $filename = shift @filenames;
    my $md5 = shift @md5s;
    $y->download($filename,$md5);
}

chdir '..';

system 'diff -r files/ got/';


=head1 NAME

Yars::Client (Yet Another REST Server Client)

=head1 SYNOPSIS

 my $r = Yars::Client->new;

 # Put a file.
 $r->upload($filename) or die $r->errorstring;
 print $r->res->headers->location;

 # Write a file to disk.
 $r->download($filename, $md5) or die $r->errorstring;
 $r->download($filename, $md5, '/tmp');   # download it to the /tmp directory
 $r->download("http://yars/0123456890abc/filename.txt"); # Write filename.txt to current directory.

 # Get the content of a file.
 my $content = $r->get($filename,$md5);

 # Put some content to a filename.
 my $content = $r->put($filename,$content);

 # Delete a file.
 $r->remove($filename, $md5) or die $r->errorstring;

 # Find the URL of a file.
 print $r->location($filename, $md5);

 print "Server version is ".$r->status->{server_version};
 my $usage = $r->disk_usage();      # Returns usage for a single server.
 my $nother_usage = Yars::Client->new(url => "http://anotherserver.nasa.gov:9999")->disk_usage();
 my $status = $r->servers_status(); # return a hash of servers, disks, and their statuses

 # Mark a disk down.
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "down" });
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "down", host => "http://someyarshost.nasa.gov" });

 # Mark a disk up.
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "up" });

=head1 DESCRIPTION

Client for Yars.

=head1 SEE ALSO

 yarsclient (executable that comes with Yars::Client)
 Clustericious::Client


