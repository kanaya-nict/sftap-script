#!/usr/bin/env perl
#

use strict;
use Socket;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::UNIX;
use JSON;
use Divide;
use FileHandle;
use MIME::Base64;

my $yarai_host = 'localhost';
my $yarai_port = 80;
#my $sftap_http_sock  = '/tmp/sf-tap/tcp/default';
my $sftap_http_sock  = '/tmp/sf-tap_tcp/tcp/default';

my $id_head  = time;
my $id_count = 0;

sub MAX_LEN { return 8192;}


my $output_dir = "tcp";
my $output_file_head = "tcp";
my $output_file_ext  = "json";

if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}

if(defined $ARGV[1]){
    $sftap_http_sock = $ARGV[1];
}

my $d;


if(-d $output_dir){
    $d = new Divide($output_dir, $output_file_head, $output_file_ext);
}

my %data_table;

sub schedule{
}

sub parse_header{
    my ($line) = @_;

    my %result = map{split(/\=/, $_)} split(/\,/, $line);

    return \%result;
}

sub create_taple {
    my ($data) = @_;
    my %table;
    $table{time}              = $data->{'time'};
    $table{vlan}              = $data->{vlan};
    $table{netid}             = $data->{netid};
    $table{'server'}={};
    $table{'server'}->{ip}    = $data->{'ip1'};
    $table{'server'}->{port}  = $data->{'port1'};
    $table{'server'}->{size}  = 0;
    $table{'client'}={};
    $table{'client'}->{ip}    = $data->{'ip2'};
    $table{'client'}->{port}  = $data->{'port2'};
    $table{'client'}->{size}  = 0;
    $table{id}                = [$id_head,$id_count];
    $id_count++;
    
    my %body;
    $body{server} = '';
    $body{client} = '';
    my $entry = [\%table, \%body];
    $data_table{$data->{'ip1'},$data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}} = $entry;
    
    return $entry;
}

sub print_data {
    my ($taple) = @_;
    my $time = $taple->{time};
    my $fh;
    if(defined $d){
        $fh = $d->get_filehandle_by_vlan($taple->{vlan}, $time, $taple->{netid});
    }
    else{
	$fh = *STDOUT
    }
    print $fh encode_json($taple), "\n";
#    print "ip=", $taple->{client}->{ip}, "time=" ,$time ,"\n";
}

my $client;

if(-S $sftap_http_sock){
    $client = IO::Socket::UNIX->new(
	Type=> SOCK_STREAM(),
	Peer=>$sftap_http_sock);
}elsif(-f $sftap_http_sock){
    $client = FileHandle->new($sftap_http_sock, "r");
}
else{
    $client = *STDIN;
}

while($_ = $client->getline){
    chop;
    if(/^ip/) {
	my $data = parse_header($_);

	if($data->{'event'} eq 'CREATED'){
	    my $taple =create_taple($data);
	    $taple->[0]->{status}= 'create';
	    print_data($taple->[0]);
	}
	elsif($data->{'event'} eq 'DESTROYED'){
	    my $taple = $data_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};
	    if(defined $taple){
		$taple->[0]->{time} = $data->{time};
#		$taple->[0]->{server}->{payload} = MIME::Base64::encode(substr($taple->[1]->{server}, 0, MAX_LEN));
#		$taple->[0]->{client}->{payload} = MIME::Base64::encode(substr($taple->[1]->{client}, 0, MAX_LEN));
		$taple->[0]->{server}->{payload} = MIME::Base64::encode($taple->[1]->{server},"");
		$taple->[0]->{client}->{payload} = MIME::Base64::encode($taple->[1]->{client},"");
		$taple->[0]->{status}= 'destroy';
		$taple->[0]->{reason}= $data->{reason};
		print_data($taple->[0]);
		delete $data_table{$data->{'ip1'},$data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};
	    }
	}
	elsif($data->{'event'} eq 'DATA'){
	    my $taple = $data_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};	
	    if(! defined $taple){
		$taple = create_taple($data);
	    }
	    $taple->[0]->{time} = $data->{time};
	    my $dir;
	    if($data->{'from'}==1){
		$dir = 'server';
	    }
	    else{
		$dir = 'client';
	    }
	    $taple->[0]->{status}= $dir;
	    my $len = $data->{'len'};
	    $taple->[0]->{$dir}->{len}   = $len;
	    $taple->[0]->{$dir}->{size} += $len;
	    my $res;
	    $client->read($res, $len);
	    delete $taple->[0]->{server}->{'body'};
	    delete $taple->[0]->{client}->{'body'};
	    $taple->[0]->{$dir}->{'body'} = MIME::Base64::encode($res, "");
	    if(length($taple->[1]->{$dir}<MAX_LEN)){
		$taple->[1]->{$dir} .= $res;
	    }
	    print_data($taple->[0]);
	}
	else{
	    print "data error$_\n";
	}
	schedule();
    }
}
