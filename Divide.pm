#!/usr/bin/env perl
#
#
package Divide;
use strict;
use JSON;
use FileHandle;

sub new {
    my ($class, $output_dir, $output_file_head, $output_file_ext, $output_file_ext2) = @_;

    my $self = {};
    bless $self, $class;

    $self->{output_dir} = $output_dir;
    $self->{output_file_head} = $output_file_head;
    $self->{output_file_ext} = $output_file_ext;
    $self->{output_file_ext2} = $output_file_ext2;

    $self->{fh_table} = {};
    $self->{entry_table} = {};
    
    return $self;
}

sub get_pathname{
    my ($self, $clnum, $year, $mon, $mday) = @_;
    my $res = sprintf("%s/%s", $self->{output_dir}, $clnum);
    return $res;
}

sub get_filename{
    my ($self, $clnum, $year, $mon, $mday, $hour, $min, $sec) = @_;
    my $path = $self->get_pathname($clnum, $year, $mon, $mday, $hour, $min, $sec);

    my $res;
    if(defined $self->{yyyymmdd}){
        $res = sprintf("%s/%s%04d-%02d-%02d_%02d.%s", 
                       $path,
                       $self->{output_file_head}, 
                       $year+1900, $mon+1, $mday,
                       $clnum, 
                       $self->{output_file_ext});
    }
    else{
        $res = sprintf("%s/%s%04d-%02d-%02d-%02d00_%02d.%s", 
                       $path,
                       $self->{output_file_head}, 
                       $year+1900, $mon+1, $mday,  $hour,
                       $clnum, 
                       $self->{output_file_ext});
    }
    return $res;
}

sub get_dirname{
    my ($self, $dst, $time) =@_;
    my $clnum = $self->get_clnum($dst);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time);
    
    my $path = $self->get_pathname($clnum, $year, $mon, $mday, $hour, $min, $sec);
    my $res = sprintf("%s/%04d-%02d-%02d",
                      $path,
                      $year+1900, $mon+1, $mday);

    if(wantarray){
        (my $time_micros = $time) =~ s/^\d+\.//;
        my $filepath = sprintf("%s/%s%04d-%02d-%02d-%02d%02d%02d_%02d_%02d.%s", 
                               $res,
                               $self->{output_file_head}, 
                               $year+1900, $mon+1, $mday,  $hour,
                               $min, $sec, $time_micros,
                               $clnum, 
                               $self->{output_file_ext2});

        return ($res, $filepath);
    }
    else{
        return $res;
    }
}

sub get_dirname_by_vlan{
    my ($self, $vlan, $time) =@_;
    my $clnum = $self->get_clnum_by_vlan($vlan);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time);
    
    my $path = $self->get_pathname($clnum, $year, $mon, $mday, $hour, $min, $sec);
    my $res = sprintf("%s/%04d-%02d-%02d",
                      $path,
                      $year+1900, $mon+1, $mday);

    if(wantarray){
        (my $time_micros = $time) =~ s/^\d+\.//;
        my $filepath = sprintf("%s/%s%04d-%02d-%02d-%02d%02d%02d_%02d_%02d.%s", 
                               $res,
                               $self->{output_file_head}, 
                               $year+1900, $mon+1, $mday,  $hour,
                               $min, $sec, $time_micros,
                               $clnum, 
                               $self->{output_file_ext2});

        return ($res, $filepath);
    }
    else{
        return $res;
    }
}

sub get_clnum{
    my ($self, $dst) =@_;
    my $clnum;

    my @ip_addr = split(/\./, $dst);


    if($ip_addr[0] == 10){
        if($ip_addr[1] == 4){
            $clnum = $ip_addr[2];
        }
        else{
            $clnum = $ip_addr[1];
        }
    }
    else{
        $clnum = $ip_addr[0].".".$ip_addr[1];
    }
    return $clnum;
}

sub get_filehandle{
    my($self, $dst, $time) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst);

    if($time=~/(\d+)\-(\d+)\-(\d+)\s+(\d+)\:(\d+)\:(\d+)/){
        ($year, $mon, $mday, $hour) = ($1-1900, $2 - 1, $3, $4);
    }
    else {
        ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time);
    }    

    my $yyyymmdd;
    if(defined $self->{yyyymmdd}){
        $yyyymmdd = sprintf("%04d-%02d-%02d", $year + 1900, $mon + 1, $mday);
    }
    else{
        $yyyymmdd = sprintf("%04d-%02d-%02d-%2d00", $year + 1900, $mon + 1, $mday, $hour);
    }
    my $clnum = $self->get_clnum($dst);

    my $fh;
    if((exists $self->{entry_table}->{$clnum})
       &&($self->{entry_table}->{$clnum} eq $yyyymmdd)){
        $fh = $self->{fh_table}->{$clnum};
    }
    else{
        if(exists $self->{fh_table}->{$clnum}){
            close $self->{fh_table}->{$clnum};
        }
        my $path = $self->get_pathname($clnum, $year, $mon, $mday, $hour, $min, $sec);
        if(! -d $path){
            #	    print "create directory=$path\n";
            mkdir $path;
        }
        my $filename = $self->get_filename($clnum, $year, $mon, $mday, $hour, $min, $sec);
        #	print "filename=$filename\n";
        $fh = new FileHandle($filename, "a+");
        $fh->autoflush(1);
        die "can not open file" if(! defined $fh);
        $self->{fh_table}->{$clnum} = $fh;
        $self->{entry_table}->{$clnum} = $yyyymmdd;
    }
    return $fh;

}

sub get_clnum_by_vlan{
    my ($self, $vlan) =@_;
    my $clnum;

    if($vlan > 3900 and $vlan<4000) {
        $clnum = ($vlan - 3900) + 127;
    }
    elsif($vlan > 3000 and $vlan < 3900) {
        $clnum = int (($vlan - 3000) / 10) + 127; 
    }
    else{
        $clnum = sprintf("%04d", $vlan);
    }
    
    return $clnum;
}

sub get_clnum_by_netid{
    my ($self, $netid, $vlan) =@_;
    my $clnum;

    $clnum = sprintf("%06d", $netid);
    
    return $clnum;
}

sub get_filehandle_by_vlan{
    my($self, $vlan, $time, $netid) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst);

    if($time=~/(\d+)\-(\d+)\-(\d+)\s+(\d+)\:(\d+)\:(\d+)/){
        ($year, $mon, $mday, $hour) = ($1-1900, $2 - 1, $3, $4);
    }
    else {
        ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time);
    }    

    my $yyyymmdd;
    if(defined $self->{yyyymmdd}){
        $yyyymmdd = sprintf("%04d-%02d-%02d", $year + 1900, $mon + 1, $mday);
    }
    else{
        $yyyymmdd = sprintf("%04d-%02d-%02d-%2d00", $year + 1900, $mon + 1, $mday, $hour);
    }
    my $clnum;
    if(defined $netid){
        $clnum = $self->get_clnum_by_netid($netid, $vlan);
    }else{
        $clnum = $self->get_clnum_by_vlan($vlan);
    }

    my $fh;
    if((exists $self->{entry_table}->{$clnum})
       &&($self->{entry_table}->{$clnum} eq $yyyymmdd)){
        $fh = $self->{fh_table}->{$clnum};
    }
    else{
        if(exists $self->{fh_table}->{$clnum}){
            close $self->{fh_table}->{$clnum};
        }
        my $path = $self->get_pathname($clnum, $year, $mon, $mday, $hour, $min, $sec);
        if(! -d $path){
            #	    print "create directory=$path\n";
            mkdir $path;
        }
        my $filename = $self->get_filename($clnum, $year, $mon, $mday, $hour, $min, $sec);
        #	print "filename=$filename\n";
        $fh = new FileHandle($filename, "a+");
        $fh->autoflush(1);
        die "can not open file" if(! defined $fh);
        $self->{fh_table}->{$clnum} = $fh;
        $self->{entry_table}->{$clnum} = $yyyymmdd;
    }
    return $fh;

}


1;
