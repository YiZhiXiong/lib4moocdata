package Model;

# Configuration
use strict;
use warnings;

##
#
# Author : Muthu Kumar C
# Created in May, 2014
#
##

# Dependencies
# External libraries
use DBI;

sub getDBHandle{	
	# Set up database connection globally
	my ($path,$unicode,$dbtype,$dbname) = @_;
	my $uname;	
	my $pswd;
	my $dsn;
	
	if(!defined $dbtype){
		#sqlite
		$uname  = 'foo';
		$pswd   = '';
		$dbname = 'cs6207.db';
		$dsn	= "dbi:SQLite:dbname=$path/$dbname";
	}
	elsif($dbtype eq 'mysql'){
		#mysql
		$uname  = 'root';
		$pswd   = 'root';
		if(!defined $dbname){
			$dbname = '$coursera_dump';
		}
		$dsn	= "DBI:mysql:database=$dbname;host=localhost;port=3306";
	}
	
	my $dbh;
	
	if (defined $unicode){
		$dbh = DBI->connect($dsn,$uname,$pswd,{sqlite_unicode => 1})
						or die "pl says Cannot connect:   $DBI::errstr\n";
	}
	else{
		#print "\n Connecting to Mysql db with $dsn with uname $uname";
		$dbh = DBI->connect($dsn,$uname,$pswd)
						or die "pl says Cannot connect:   $DBI::errstr\n";
	}
	return $dbh;
}

sub getCourses{
	my ($dbh, $dataset, $downloaded) = @_;
	my $query = "select distinct courseid from forum where ";

	if (defined $downloaded){
		$query .= "downloaded = $downloaded";
	}else{
		$query .= "downloaded = 0";
	}
	
	if (defined $dataset){
		$query .= " and dataset = \'$dataset\'";
	}
	
	my $courses = $dbh->selectcol_arrayref($query) or die "$DBI::errstr\n";
	return $courses;
}

sub getforumname{
	my ($dbh, $forumid, $courseid) = @_;
	my $query = "select forumname from forum where id = $forumid and courseid = \'$courseid\'";
	my $forumname = $dbh->selectrow_arrayref($query) or die "$DBI::errstr\n $query";
	return $forumname;
}

sub getSubForums{
	my ($dbh,$courses,$forumid,$forumname,$dataset, $recrawl) = @_;
	my $query = "select id,courseid,forumname from forum where downloaded ";
	if(defined $recrawl){
		$query .= " = 1";
	}
	else{
		$query .= " is null";
	}
	
	if(defined $courses){
		$query = appendListtoQuery($query,$courses,"and");
	}
	if(defined $forumid){
		$query .= " and id = $forumid";
	}
	if(defined $forumname){
		$query .= " and forumname = \'$forumname\'";
	}	
	print "Executing $query\n";
	my $subforums = $dbh->selectall_arrayref($query) or die "$DBI::errstr\n";
	return $subforums;
}

sub appendListtoQuery{
	my($query, $list, $predicate ,$clause) = @_;
	if(defined $list){
		$query	.= " $clause $predicate in ( ";
		foreach my $item (@$list){
			$query .= " \'$item\',";
		}
		$query  =~ s/\,$//;
		$query .= " ) ";
	}
	return $query;
}

sub getNumValidThreads{
	my($dbh,$courses) = @_;
	if (!defined $courses){
		die "\n Model-getNumValidThreads: no input corpus to count on.";
	}
	my %number_of_threads = ();
	my $numthreads = 0;
	
	my $qryinst = "select count(1) from (select distinct threadid, courseid from termFreqC14inst) ";
	
	$qryinst = appendListtoQuery($qryinst,$courses, ' courseid ', ' where ');
	$numthreads += @{$dbh->selectcol_arrayref($qryinst)}[0];
	
	my $qrynoinst = "select count(1) from (select distinct threadid, courseid from termFreqC14noinst)";
	$qrynoinst = appendListtoQuery($qrynoinst,$courses, ' courseid ', ' where ');	
	$numthreads += @{$dbh->selectcol_arrayref($qrynoinst)}[0];

	return $numthreads;
}
	
sub getNumThreads{
	my( $dbh,$courses ) = @_;
	
	my %number_of_threads = ();
	my %number_of_interventions = ();
		
	my $forumidsquery = "select courseid, sum(numthreads), sum(numinter) from forum 
							where courseid not in( 'ml' )
							and forumname in ('Errata','Exam','Lecture','Homework') ";
	if(defined $courses){
		$forumidsquery .= "and courseid in ( ";
		foreach my $course (@$courses){
			$forumidsquery .= " \'$course\',";
		}
		$forumidsquery =~ s/\,$//;
		$forumidsquery .= " ) ";
	}					
							
	$forumidsquery .= "group by courseid";
	
	my $forumrows = $dbh->selectall_arrayref($forumidsquery) 
						or die "courses query failed! \t $forumidsquery";
	foreach my $forumrow ( @$forumrows ){
		my $coursecode = @$forumrow[0];
		my $num_threads = @$forumrow[1];
		my $num_inter = @$forumrow[2];
		
		#TODO prepare following query outside the loop
		if(!exists $number_of_threads{$coursecode}){
			$number_of_threads{$coursecode} = $num_threads;
		}
		else{
			$number_of_threads{$coursecode} += $num_threads;
		}
		
		if(!exists $number_of_interventions{$coursecode}){
			$number_of_interventions{$coursecode} = $num_threads;
		}
		else{
			$number_of_interventions{$coursecode} += $num_threads;
		}
	}
	return (\%number_of_threads, \%number_of_interventions);
}

sub getIntructorTAOnlyThreads{
	my ($dbh, $courseid, $forumid) = @_;
	my $query = "select distinct thread_id from post3 where courseid=? ";
	
	if(defined $forumid){
		$query .= " and forumid=? ";
	}
	print "Executing.. $query \n";
	my $sth = $dbh->prepare($query)
					or die "Couldn't prepare statement: " . $dbh->errstr;
	if (defined $forumid){
		$sth->execute($courseid,$forumid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	else{
		$sth->execute($courseid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	my $threadids = $sth->fetchall_arrayref();
	
	my $where = "id in ( ";
	foreach my $threadid(@$threadids){
		print "$threadid->[0] \t $courseid \t $forumid \n";
		$where .= "$threadid->[0],";
	}
	$where =~ s/\,$//;
	$where .= ")";
	$threadids = Getthreadids($dbh, $courseid, $forumid, $where);
	return $threadids;
}

sub Getthreadids{
	my ( $dbh, $courseid, $forumid, $where ) = @_;
	my $query = "select id,docid,courseid,inst_replied,title,posted_time from thread where courseid=? ";
	
	if(!defined $courseid){
		die "Exception: Model-Getthreadids: $courseid not defined \n";
	}
	
	if(defined $forumid){
		$query .= " and forumid=? ";
	}
	if(defined $where){
		$query .= " and ".$where;
	}
	
	$query .= " order by posted_time asc";
	
	print "\nExecuting.. $query ";
	my $sth = $dbh->prepare($query)
						or die "Couldn't prepare statement: " . $dbh->errstr;
	if (defined $forumid){
		$sth->execute($courseid,$forumid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	else{
		$sth->execute($courseid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	my $threadids = $sth->fetchall_arrayref();
	return $threadids;
}

sub getthread{
	my ($dbh,$docid) = @_;
	my $row = $dbh->selectrow_arrayref("select courseid, id, forumid from thread where docid = $docid");
	if (!defined $row){
		die "Exception: Model-getthread: thread $docid not found in thread table";
	}
	my @threadrow = @{$row};
	my $coursecode = $threadrow[0];
	my $threadid= $threadrow[1];
	my $forumid= $threadrow[2];
	return ($threadid,$coursecode,$forumid);
}

sub getThreadtype{
	my ($dbh,$docid) = @_;
	my $query = "select forumname from forum 
				where id = (select forumid from thread where docid = $docid) 
				and courseid = (select courseid from thread where docid = $docid)";
	my $type = @{$dbh->selectcol_arrayref($query)}[0];
	return $type;
}

sub hasInstReplied{
	my($dbh, $docid) = @_;
	my $query = "select inst_replied from thread where docid = $docid";
	my $inst_replied = @{$dbh->selectcol_arrayref($query)}[0];
	return $inst_replied;
}

sub updateHash{
	my ($terms_per_course,$terms,$term_course_count) = @_;
	
	foreach my $termid (keys %$terms_per_course){
		my $courseid 	= $terms_per_course->{$termid}{'courseid'};
		my $term 		= $terms_per_course->{$termid}{'term'};	
		my $df			= $terms_per_course->{$termid}{'df'};
		$terms->{$courseid}{$termid}{$term} = $df;
		$term_course_count->{$termid}{$courseid} = 1;
	}
	return ($terms, $term_course_count);
}
=======
package Model;

# Configuration
use strict;
use warnings;

##
#
# Author : Muthu Kumar C
# Created in May, 2014
#
##

# Dependencies
# External libraries
use DBI;

sub getDBHandle{	
	# Set up database connection globally
	my ($path,$unicode,$dbtype,$dbname) = @_;
	my $uname;	
	my $pswd;
	my $dsn;
	
	if(!defined $dbtype){
		#sqlite
		$uname  = 'foo';
		$pswd   = '';
		$dbname = 'cs6207.db';
		$dsn	= "dbi:SQLite:dbname=$path/$dbname";
	}
	elsif($dbtype eq 'mysql'){
		#mysql
		$uname  = 'root';
		$pswd   = 'root';
		if(!defined $dbname){
			$dbname = '$coursera_dump';
		}
		$dsn	= "DBI:mysql:database=$dbname;host=localhost;port=3306";
	}
	
	my $dbh;
	
	if (defined $unicode){
		$dbh = DBI->connect($dsn,$uname,$pswd,{sqlite_unicode => 1})
						or die "pl says Cannot connect:   $DBI::errstr\n";
	}
	else{
		#print "\n Connecting to Mysql db with $dsn with uname $uname";
		$dbh = DBI->connect($dsn,$uname,$pswd)
						or die "pl says Cannot connect:   $DBI::errstr\n";
	}
	return $dbh;
}

sub getCourses{
	my ($dbh, $dataset, $downloaded) = @_;
	my $query = "select distinct courseid from forum where ";

	if (defined $downloaded){
		$query .= "downloaded = $downloaded";
	}else{
		$query .= "downloaded = 0";
	}
	
	if (defined $dataset){
		$query .= " and dataset = \'$dataset\'";
	}
	
	my $courses = $dbh->selectcol_arrayref($query) or die "$DBI::errstr\n";
	return $courses;
}

sub getforumname{
	my ($dbh, $forumid, $courseid) = @_;
	my $query = "select forumname from forum where id = $forumid and courseid = \'$courseid\'";
	my $forumname = $dbh->selectrow_arrayref($query) or die "$DBI::errstr\n $query";
	return $forumname;
}

sub getSubForums{
	my ($dbh,$courses,$forumid,$forumname,$dataset, $recrawl) = @_;
	my $query = "select id,courseid,forumname from forum where downloaded ";
	if(defined $recrawl){
		$query .= " = 1";
	}
	else{
		$query .= " is null";
	}
	
	if(defined $courses){
		$query = appendListtoQuery($query,$courses,"and");
	}
	if(defined $forumid){
		$query .= " and id = $forumid";
	}
	if(defined $forumname){
		$query .= " and forumname = \'$forumname\'";
	}	
	print "Executing $query\n";
	my $subforums = $dbh->selectall_arrayref($query) or die "$DBI::errstr\n";
	return $subforums;
}

sub appendListtoQuery{
	my($query, $list, $predicate ,$clause) = @_;
	if(defined $list){
		$query	.= " $clause $predicate in ( ";
		foreach my $item (@$list){
			$query .= " \'$item\',";
		}
		$query  =~ s/\,$//;
		$query .= " ) ";
	}
	return $query;
}

sub getNumValidThreads{
	my($dbh,$courses) = @_;
	if (!defined $courses){
		die "\n Model-getNumValidThreads: no input corpus to count on.";
	}
	my %number_of_threads = ();
	my $numthreads = 0;
	
	my $qryinst = "select count(1) from (select distinct threadid, courseid from termFreqC14inst) ";
	
	$qryinst = appendListtoQuery($qryinst,$courses, ' courseid ', ' where ');
	$numthreads += @{$dbh->selectcol_arrayref($qryinst)}[0];
	
	my $qrynoinst = "select count(1) from (select distinct threadid, courseid from termFreqC14noinst)";
	$qrynoinst = appendListtoQuery($qrynoinst,$courses, ' courseid ', ' where ');	
	$numthreads += @{$dbh->selectcol_arrayref($qrynoinst)}[0];

	return $numthreads;
}
	
sub getNumThreads{
	my( $dbh,$courses ) = @_;
	
	my %number_of_threads = ();
	my %number_of_interventions = ();
		
	my $forumidsquery = "select courseid, sum(numthreads), sum(numinter) from forum 
							where courseid not in( 'ml' )
							and forumname in ('Errata','Exam','Lecture','Homework') ";
	if(defined $courses){
		$forumidsquery .= "and courseid in ( ";
		foreach my $course (@$courses){
			$forumidsquery .= " \'$course\',";
		}
		$forumidsquery =~ s/\,$//;
		$forumidsquery .= " ) ";
	}					
							
	$forumidsquery .= "group by courseid";
	
	my $forumrows = $dbh->selectall_arrayref($forumidsquery) 
						or die "courses query failed! \t $forumidsquery";
	foreach my $forumrow ( @$forumrows ){
		my $coursecode = @$forumrow[0];
		my $num_threads = @$forumrow[1];
		my $num_inter = @$forumrow[2];
		
		#TODO prepare following query outside the loop
		if(!exists $number_of_threads{$coursecode}){
			$number_of_threads{$coursecode} = $num_threads;
		}
		else{
			$number_of_threads{$coursecode} += $num_threads;
		}
		
		if(!exists $number_of_interventions{$coursecode}){
			$number_of_interventions{$coursecode} = $num_threads;
		}
		else{
			$number_of_interventions{$coursecode} += $num_threads;
		}
	}
	return (\%number_of_threads, \%number_of_interventions);
}

sub getIntructorTAOnlyThreads{
	my ($dbh, $courseid, $forumid) = @_;
	my $query = "select distinct thread_id from post3 where courseid=? ";
	
	if(defined $forumid){
		$query .= " and forumid=? ";
	}
	print "Executing.. $query \n";
	my $sth = $dbh->prepare($query)
					or die "Couldn't prepare statement: " . $dbh->errstr;
	if (defined $forumid){
		$sth->execute($courseid,$forumid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	else{
		$sth->execute($courseid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	my $threadids = $sth->fetchall_arrayref();
	
	my $where = "id in ( ";
	foreach my $threadid(@$threadids){
		print "$threadid->[0] \t $courseid \t $forumid \n";
		$where .= "$threadid->[0],";
	}
	$where =~ s/\,$//;
	$where .= ")";
	$threadids = Getthreadids($dbh, $courseid, $forumid, $where);
	return $threadids;
}

sub Getthreadids{
	my ( $dbh, $courseid, $forumid, $where ) = @_;
	my $query = "select id,docid,courseid,inst_replied,title,posted_time from thread where courseid=? ";
	
	if(!defined $courseid){
		die "Exception: Model-Getthreadids: $courseid not defined \n";
	}
	
	if(defined $forumid){
		$query .= " and forumid=? ";
	}
	if(defined $where){
		$query .= " and ".$where;
	}
	
	$query .= " order by posted_time asc";
	
	print "\nExecuting.. $query ";
	my $sth = $dbh->prepare($query)
						or die "Couldn't prepare statement: " . $dbh->errstr;
	if (defined $forumid){
		$sth->execute($courseid,$forumid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	else{
		$sth->execute($courseid)
							or die "Couldn't execute statement: " . $query->errstr;
	}
	my $threadids = $sth->fetchall_arrayref();
	return $threadids;
}

sub getthread{
	my ($dbh,$docid) = @_;
	my $row = $dbh->selectrow_arrayref("select courseid, id, forumid from thread where docid = $docid");
	if (!defined $row){
		die "Exception: Model-getthread: thread $docid not found in thread table";
	}
	my @threadrow = @{$row};
	my $coursecode = $threadrow[0];
	my $threadid= $threadrow[1];
	my $forumid= $threadrow[2];
	return ($threadid,$coursecode,$forumid);
}

sub getThreadtype{
	my ($dbh,$docid) = @_;
	my $query = "select forumname from forum 
				where id = (select forumid from thread where docid = $docid) 
				and courseid = (select courseid from thread where docid = $docid)";
	my $type = @{$dbh->selectcol_arrayref($query)}[0];
	return $type;
}

sub hasInstReplied{
	my($dbh, $docid) = @_;
	my $query = "select inst_replied from thread where docid = $docid";
	my $inst_replied = @{$dbh->selectcol_arrayref($query)}[0];
	return $inst_replied;
}

sub updateHash{
	my ($terms_per_course,$terms,$term_course_count) = @_;
	
	foreach my $termid (keys %$terms_per_course){
		my $courseid 	= $terms_per_course->{$termid}{'courseid'};
		my $term 		= $terms_per_course->{$termid}{'term'};	
		my $df			= $terms_per_course->{$termid}{'df'};
		$terms->{$courseid}{$termid}{$term} = $df;
		$term_course_count->{$termid}{$courseid} = 1;
	}
	return ($terms, $term_course_count);
}
1;