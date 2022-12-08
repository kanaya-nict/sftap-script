#!/usr/bin/env perl
#
use strict;
use JSON;
use FileHandle;
use Divide;

my $output_dir = "icmp";
my $output_file_head = "icmp";
my $output_file_ext  = "json";
my $add_date_flag    = 0;


if((defined $ARGV[0]) and ($ARGV[0] eq "-d")){
    $add_date_flag = 1;
    shift @ARGV;
}

if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}

if(defined $ARGV[1]){
    $output_file_head = $ARGV[1];
}

my $d = new Divide($output_dir, $output_file_head, $output_file_ext);

$|=1;
while($_=<STDIN>){
    last if(! defined $_);
    if(/\"vlan\"\:\"?([\d\.]+)/){
        my $vlan = $1;
        my $netid;
        if(/\"netid\"\:\"?([\d\.]+)/){
            $netid=$1;
        }
        
        if(/\"time\"\:\"?([\d\.]+)/){
            my $time = $1;
            #	    print STDERR "src=$src, time=$time\n";
            if($add_date_flag){
                chop;chop;
                my $date = time;
                $_ = "$_,\"date\":$date}\n";
            }
            my $fh = $d->get_filehandle_by_vlan($vlan, $time, $netid);
            if(defined $fh){
                print $fh $_;
            }
        }
    }
}
