
use strict;
use warnings;

use DateTime;
use File::Copy;
use File::Spec::Functions;
use LWP::UserAgent;
use XML::Simple;
use JSON;


my $checking_dir = catdir('z:','checkshipped');
#my $checking_dir = catdir('c:', 'backup', 'Need to ship', 'checkshipped');
my $checked_dir  = catdir($checking_dir,'checked');

my $current = time;
my @shipped;
my @late;
my %params = ();

my $last = 0;
my %files = get_sorted_files($checking_dir);

foreach my $key (sort{$files{$a} <=> $files{$b}} keys %files) {
    next if ($current - $files{$key} > 30*24*3600);	
	next if ($key !~ m/1Z.+\-.*/);	
	
	my $tracking_id = $key;
	$tracking_id =~ s/(1Z.+?)\-.*/$1/;
	$tracking_id =~ s/^\s+|\s+$//g;
	next if (length $tracking_id != 18);
	
	my $created = DateTime->from_epoch( epoch => $files{$key}, time_zone => 'America/New_York' );
	my $today =  DateTime->from_epoch( epoch => $current, time_zone => 'America/New_York' );	
	my $c_week = ($created->day_of_week()<6) ? $created->week_number() : $created->week_number()+1;
	my $c_day = ($created->day_of_week()<6) ? $created->day_of_week() : 1;
	my $t_day = ($today->day_of_week()<6) ? $today->day_of_week() : 5;
	my $diff = ($today->week_number()-$c_week)*5+($t_day-$c_day);
	
	$params{$tracking_id} = {'fname'=>$key, 'diff'=>$diff};
	track(\%params); 
	%params = ();
	
	#if (scalar(keys %params) >= 25) {
	#	track(\%params); 
	#	%params = ();		
	#}
		
    print "$tracking_id\t", scalar localtime($files{$key}), "\n";	
}

#track(\%params) if (scalar(keys %params));

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
	my @id = keys(%$params);
	my $trackingNumber = $id[0]; #"1Z165W8V0325757740";
	#my $trackingNumber = "1Z6F16334294370248";	
	
	my $ua = LWP::UserAgent->new();
	my $req = HTTP::Request->new(POST =>"https://wwwcie.ups.com/rest/Track");
	$req->header('Content-Type' => 'application/json');
	$req->content(qq({ "UPSSecurity": { "UsernameToken": { "Username": "durui", "Password": "Dr721225!" }, "ServiceAccessToken": { "AccessLicenseNumber": "4D76FDD6EF9B2472" } }, "TrackRequest": { "Request": { "RequestOption": "1", "TransactionReference": { "CustomerContext": "Your Test Case Summary Description" } }, "InquiryNumber": "$trackingNumber" } }));
	
	my $response = $ua->request($req);
				
	if ($response->is_success) {
	  my $json = JSON->new->allow_nonref;
      my $data = $json->decode($response->content());
	  
	  my $shipped = 0;
	  if ($data->{'TrackResponse'}->{'Response'}->{'ResponseStatus'}->{'Code'} == 1) {
		if (ref($data->{'TrackResponse'}->{'Shipment'}->{'Package'}) eq 'ARRAY') {
		  # multiple packages
		  $shipped = 1;
		  
		  my @packages = @{$data->{'TrackResponse'}->{'Shipment'}->{'Package'}};
		  foreach my $package (@packages) {
		    if (ref($package->{'Activity'}) ne 'ARRAY' || scalar($package->{'Activity'})<2) {
			  $shipped = 0;
			  last;
			}				
		  }		  
		} elsif (ref($data->{'TrackResponse'}->{'Shipment'}->{'Package'}->{'Activity'}) eq 'ARRAY' 
		  && scalar($data->{'TrackResponse'}->{'Shipment'}->{'Package'}->{'Activity'})>1) {
		  $shipped = 1;
		}				 
	  }
	  
	  if ($shipped) {
		push @shipped, $params->{$trackingNumber}->{'fname'};
 	  } elsif ($params->{$trackingNumber}->{'diff'} >= 3) {
		push @late, $params->{$trackingNumber}->{'fname'};			
	  }
      my $t = 1;	  
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

