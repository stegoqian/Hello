
use strict;
use warnings;

use DateTime;
use File::Copy;
use File::Spec::Functions;
use LWP::UserAgent;
use XML::Simple;
use JSON;


#my $checking_dir = catdir('c:', 'backup', 'Need to ship', 'checkshipped');
my $checking_dir = catdir('z:','checkshipped');
my $checked_dir  = catdir($checking_dir,'checked');

my $current = time;
my @shipped;
my @late;
my %params = ();

my $last = 0;
my %files = get_sorted_files($checking_dir);

my $browser = LWP::UserAgent->new(timeout => 10);
my $xmlParser = new XML::Simple();

foreach my $key (sort{$files{$b} <=> $files{$a}} keys %files) {
    last if ($current - $files{$key} > 14*24*3600);	
	next if ($key !~ m/\d+\-.*/);	
	
	my $tracking_id = $key;
	$tracking_id =~ s/(\d+)\-.*/$1/;
	next if (length $tracking_id != 22);
	
	my $created = DateTime->from_epoch( epoch => $files{$key}, time_zone => 'America/New_York' );
	my $today =  DateTime->from_epoch( epoch => $current, time_zone => 'America/New_York' );	
	my $c_week = ($created->day_of_week()<6) ? $created->week_number() : $created->week_number()+1;
	my $c_day = ($created->day_of_week()<6) ? $created->day_of_week() : 1;
	my $t_day = ($today->day_of_week()<6) ? $today->day_of_week() : 5;
	my $diff = ($today->week_number()-$c_week)*5+($t_day-$c_day);
	
	$params{$tracking_id} = {'fname'=>$key, 'diff'=>$diff};
	if (scalar(keys %params) >= 10) {
		track(\%params); 
		%params = ();		
	}
		
    print "$tracking_id\t", scalar localtime($files{$key}), "\n";	
}

track(\%params) if (scalar(keys %params));

if (scalar @shipped) {
	foreach my $fname (@shipped) {
		move(catfile($checking_dir, $fname), catfile($checked_dir, $fname));
	}
}

if (scalar @late) {
  my $result = File::Spec->catfile('c:','NeedShip','A','FEDEX_NOT_SHIPPED.txt');
  open(my $fh, '>', $result) or die "cannot open < $result: $!";
  for my $late_name (@late) {
    print $fh "$late_name\n";
  }  
  
  for my $late_id (@late) {
    $late_id =~ s/(\d+)\-.*/$1/;
    print $fh "$late_id\n";
  }
  close($fh);
}

sub track {
	my $params = shift; 	
	
    my $url = q(https://secure.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML=);
	
	my $xml = q(<TrackRequest USERID="848RYATE2213">);
	foreach my $key (keys %$params) {
	  $xml = $xml . '<TrackID ID="' . $key . '"></TrackID>';
	}
	$xml = $xml . '</TrackRequest>';

	$url = $url . $xml;
	my $trackingReq = HTTP::Request->new(GET => $url);
    my $trackingResp = $browser->request($trackingReq);
  		
	if ($trackingResp->is_success) {	
        my $data = $xmlParser->XMLin($trackingResp->content(), ForceArray=>['TrackInfo', 'TrackDetail']);
		
     	foreach my $tracking (@{$data->{'TrackInfo'}}) {
		    my $id = $tracking->{'ID'};
			
			if (exists($tracking->{'TrackDetail'}) && scalar(@{$tracking->{'TrackDetail'}}) > 1) {
			    $params->{$id}->{'shipped'} = 1;
			} else {
			    $params->{$id}->{'shipped'} = 0;
			}
			
			if ($params->{$id}->{'shipped'}) {
				push @shipped, $params->{$id}->{'fname'};
			} elsif ($params->{$id}->{'diff'} >= 3) {
				push @late, $params->{$id}->{'fname'};
			}
		}
		my $t=1;
	}		
}
		
sub hash_walk {
    my ($hash, $key_list) = @_;
    while (my ($k, $v) = each %$hash) {
        # Keep track of the hierarchy of keys, in case
        # our callback needs it.
        push @$key_list, $k;

		if ($k eq 'PackageCount' && ref($v) eq 'SCALAR') {
			return $v;
		}
        elsif (ref($v) eq 'HASH') {
            # Recurse. BUG what if its an array of HASH
            return hash_walk($v, $key_list);
        }        

        pop @$key_list;
    }
	
	return -1;
}

#map  { "$path/$_" }
sub get_sorted_files {
   my $path = shift;
   opendir my($dir), $path or die "can't opendir $path: $!";
   my %hash = map {$_ => (stat("$path/$_"))[9]}           
           grep { m/.*/i }
           readdir $dir;
   closedir $dir;
   return %hash;
}

