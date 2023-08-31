#!/usr/bin/env perl
#

use strict;
use Socket;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::UNIX;
use XML::Simple;
use JSON;
use FileHandle;
use Divide;

my $yarai_host = 'localhost';
my $yarai_port = 80;
my $sftap_http_sock  = '/tmp/sf-tap/tcp/http';

my $xml = XML::Simple->new;

my $output_dir = "yarai";
my $output_file_head = "yarai";
my $output_file_ext  = "json";

if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}

my $d = new Divide($output_dir, $output_file_head, $output_file_ext);

my %data_table;

sub is_yarai_agent{
    my ($data) = @_;

    return ($data->{'ip1'}=~/10\.\d+\.8\.200/) || ($data->{'ip1'}=~/203.0.8.200/)
	|| ($data->{'ip1'} eq "172.16.8.200");
#    return ($data->{'ip1'}=~/10\.\d+\.8\.200/) || ($data->{'ip1'}=~/203.0.113.56/)
#	|| ($data->{'ip1'} eq "172.16.18.200");
}

sub parse_yarai_data{
    my ($body, $vlan, $netid) = (@_, 0xFFFFFFFF);

    if($body =~ s/.*\xd\xa\xd\xa(\<\?xml version=\"1\.0\" encoding\=\"utf-8\"\?\>[\xd\xa]+\<nirvana_request message_type)/$1/s){
	my $data = eval{$xml->XMLin($body)};
	return if(!defined $data);
	
	if(exists $data->{'log_setting_list'}) {
	    delete $data->{'log_setting_list'};
	}
	if(exists $data->{'yarai_settings'}){
	    delete $data->{'yarai_settings'};
	}
	
	my $json_text = encode_json($data);
	my $time = $data->{request_datetime};
	
	my $fh = $d->get_filehandle_by_vlan($vlan, $time, $netid);
	
	print $fh "$json_text\n";
    }
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
    $table{'server'}={};
    $table{'server'}->{ip}    = $data->{'ip1'};
    $table{'server'}->{port}  = $data->{'port1'};
    $table{'server'}->{body}  = "";
    $table{'client'}={};
    $table{'client'}->{ip}    = $data->{'ip2'};
    $table{'client'}->{port}  = $data->{'port2'};
    $table{'client'}->{size}  = 0;
    $table{'client'}->{body}  = "";
    $table{vlan}              = $data->{vlan};
    $table{netid}              = $data->{netid};
    
    my $entry = \%table;
    $data_table{$data->{'ip1'},$data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}} = $entry;
    
    return $entry;
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
	next if(!is_yarai_agent($data));

	if($data->{'event'} eq 'CREATED'){
	    my $taple =create_taple($data);
	    $taple->{status}= 'create';
	}
	elsif($data->{'event'} eq 'DESTROYED'){
	    my $taple = $data_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};		
	    if(defined $taple){
		$taple->{time} = $data->{time};
		$taple->{status}= 'destroy';
		$taple->{reason}= $data->{reason};
		parse_yarai_data($taple->{client}->{body}, $taple->{vlan}, $taple->{netid});
		delete $data_table{$data->{'ip1'},$data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};
	    }
	}
	elsif($data->{'event'} eq 'DATA'){
	    my $taple = $data_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}, $data->{netid}};		
	    if(! defined $taple){
		$taple = create_taple($data);
	    }
	    $taple->{time} = $data->{time};
	    my $dir;
	    if($data->{'from'}==1){
		$dir = 'server';
	    }
	    else{
		$dir = 'client';
	    }
	    $taple->{status}= $dir;
	    my $len = $data->{'len'};
	    $taple->{$dir}->{size} += $len;
	    my $res;
	    $client->read($res, $len);
	    $taple->{$dir}->{'body'} .= $res;
	}
	else{
	    print "data error$_\n";
	}
    }
}
