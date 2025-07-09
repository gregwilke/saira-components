return 1;

# *****************************************************************************
# Name:          rl_validate.pm
# Description:   pre-validate RL release csv file prior to database load
# *****************************************************************************
# Program History for Format Ver 4.2
# INT  DATE      Comments
# ---  ----      -------
# DLW  20230628  Begin modifiacations for Format Ver 4.2 
#                Expand comments from 80 to 200 characters
#                Removed kgt code
#                Added $TESTING, $skip_expireDate & $skip_baseDate checks
#
# DLW  20250513  Add check for non-ascii characters in comments field 
#------------------------------------------------------------------------------
# Program History prior to Format Ver 4.2
# ---  --------  --------
# DLW  20030716  Ported from Onco System 
# DLW  20031113  Check for nulls in submission date before setting to
#                todays date when running in cdev mode 
# DLW  20060123  Add MSG Message when first or last release date is less
#                than the brood_year
# DLW  20080227  Add field length check to comments field.
# DLW  20080326  Corrected unitialized value in printf of line 709 rearing_type
# DLW  20090310  Modifications for Ver 4.1 Validation
# JRL  20090410  Modifications for Ver 4.1 Validation, related_group_id analysis
# JRL  20090923  related_group_id analysis, altered array rl_rgid_newset w/ fixes
# DLW  20091215  Add mid-year check if Brood year < current year - 2 fish too old
# DLW  20100128  Added submission_date check for full 8 digit date 
#                and limited isExpiredDate to 30 days
# DLW  20100302  Added Description request comment for VALIDATED data set
# JRL  20110211  Added function filter_csv to run before doing CSV check 
# DLW  20110602  Added update to check re-submitted tag codes against
#                existing recoveries for changed species, brood_year
#                or first_release_date
# JRL  20110926  In Cross-check code section, changed error_exit code to data error
#                condition.
# DLW  20120813  crosscheck_fields routies were written with a possible endless loop
#                 Add "last" to exit loop if value not found in crosscheck lookup
#                If status 1 recoveries occur of destroyed fish then a resubmission
#                of the tag code requries that the existing release record in the 
#                database be changed to a warning before the new release can validate.
# DLW  20121018  Updated error messages in check mark routine to avoid redundant use 
#                of "mark" word in messages.
# JRL  20131125  Added check: release_location_code reqd if study_integrity not 'D'.
# DLW  20131204  Added length check to related_group_id field
# DLW  20140808  Replace DBI::CSV routine with Text::CSV to avoid records dropped from
#                processing when double quotes '"' are present within a field.
# DLW  20150120  Replace minimum year 1950 with 1900 to accomodate earlier releases
#                beginning in 1910 by CDFO impacts brood_year, group_year, first &
#                last_release_data_year (8 Edits))
# DLW  20150514  Added check for number of tag_code_or_release_id digits for tag_type
#                '15' or '3' - should be 10 digits instead of 6.
# DLW  20160525  Added &kgt_type_exists check to see if purchased
#                (kgt - known good tags) tag type matches release tag_type               
# DLW  20160826  Updated kgt lookup for re-used tags.  Remove * instance before lookup
# DLW  20161028  Fixed unexpected change from previous update where some mis-matched
#                tag |MSG| messages are not being generated after using hash lookup 
#                in cwt_defns.pm instead of isKgtTypeMismatch in tag_analyze
# DLW  20170118  Add check to confirm reporting_agency in file matches agency submitted               
# DLW  20180328  Add check and message for first_release_year == brood_year
# DLW  20200211  Comment out KGT check and brood_year for ! records check
# -------------------------------------------------------------------
$| = 1;

my $return_errors = 0;

sub rl_validate {

  #TESTING variables
  my $TESTING             = "N";     # "Y" for testing
  my $skip_expiredDate    = "N";     # "Y" to skip isExpiredDate check
  my $skip_baseDate       = "N";     # "Y" to skip baseDateOfSubmission check

  my $error_cnt   = 0;
  my $message_cnt = 0;
  my $validated   = 0;
  my $unvalidated = 0;
  my $baseDateOfSubmission = "";
  my $baseAgencyCodeReporting = "";
  my %tagCode_id;
  my $from_year = "";
  my $from_month = "";
  my $from_day = "";
  my $from_date = "";
  my $to_year = "";
  my $to_month = "";
  my $to_day = "";
  my $to_date = "";
  my $midyearyr = ($yearToday - 2);
  my $rl_first_date = "";
  my $j = 0;
  my $record_count = 0;
  my $data_count = 0;

  # Print header for log file
  printf(scalar(localtime) . ": STARTING rl_validate.pm \n");

  # Capture todays date to subsitute with submission_date for cdev testing 
  $dateToday = sprintf "%04d%02d%02d", sub {($_[5]+1900, $_[4]+1, $_[3])}->(localtime);
  printf(scalar(localtime) . ": Date Today is $dateToday \n");
  
  # Check CSV file format
  if (!(&csv_file_valid("$uvalpath/$std_file_name", 41))) {
    $valid = 0;
    &error_exit("rl_validate","Invalid CSV file format, no validation performed");
  }

  # Check for non-ascii characters
  if (!(&csv_check_ascii("$uvalpath/$std_file_name"))) {
    $valid = 0;
    &error_exit("rl_validate","Non-ASCII characters in file, no validation performed");
  }

  printf(scalar(localtime) . ": VALIDATING release records.... \n");
  my $total_csv_cnt = (`wc -l $uvalpath/$std_file_name | awk '{print \$1}'` -1); #skip header

  # Connect open and read the csv file
  my $csv = Text::CSV->new ( { binary => 1,
                             allow_loose_quotes => 0,
                             escape_char => '"',} )
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();

  open (CSV, "$uvalpath/$std_file_name") or die "Could not open $uvalpath/$std_file_name:$!\n";
  while (<CSV>) {
    $record_count++;
    if ( ! $csv->parse ($_)) {
        $error = $csv->error_diag ();
        $valid = 0;
        printf "            ; |ERR|  CSV error on record no. [%s];  --->[%s]\n", $record_count, $error;
        &error_exit("rl_validate","CSV error on record $record_count - $error");
    }

#  # OPTIONAL print line to monitor successful records while TESTING
#  if ($TESTING eq "Y") {
#     printf "Processing Record Number ;  --->[%s]\n", $record_count;
#  }

    my ($record_code, 
      $format_version, 
      $submission_date,
      $reporting_agency,
      $release_agency,
      $coordinator,
      $tag_code_or_release_id,
      $tag_type,
      $first_sequential_number,
      $last_sequential_number,
      $related_group_type,
      $related_group_id,
      $species,
      $run,
      $brood_year,
      $first_release_date,
      $last_release_date,
      $release_location_code,
      $hatchery_location_code,
      $stock_location_code,
      $release_stage,
      $rearing_type,
      $study_type,
      $release_strategy,
      $avg_weight,
      $avg_length,
      $study_integrity,
      $cwt_1st_mark,
      $cwt_1st_mark_count,
      $cwt_2nd_mark,
      $cwt_2nd_mark_count,
      $non_cwt_1st_mark,
      $non_cwt_1st_mark_count,
      $non_cwt_2nd_mark,
      $non_cwt_2nd_mark_count,
      $counting_method,
      $tag_loss_rate,
      $tag_loss_days,
      $tag_loss_sample_size,
      $tag_reused,
      $comments) = $csv->fields ();

  # Skip Header Record
  if ($record_count == 1) {
    next;   # Skip HEADER record and read next for DATA record
  } else {
    $data_count++;
  }

#  # OPTIONAL print line while TESTING
#  if ($TESTING eq "Y") {
#    print "$data_count - $record_code\n"; #Check for successfully parsed records
#  }

  # do field validations
  my $valid = 1; # set $valid = 0 if any field validations fail

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% record_code  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($record_code eq "") {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  record_code required but missing;  --->[%s]\n", $tag_code_or_release_id, $record_code; 
    next;
  } elsif (($record_code ne "T") && ($record_code ne "N")) {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  record_code must be 'T' or 'N';  --->[%s]\n", $tag_code_or_release_id, $record_code; 
    next;
  }  

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $format_version %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($format_version eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  format_version required but missing;  --->[%s]\n", $tag_code_or_release_id, $format_version; 
  } elsif (!($format_version =~ /^$current_format/)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  format_version must be '%s';  --->[%s]\n", $tag_code_or_release_id, $current_format, $format_version;
  }
    
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%% $submission_date %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%% NOTE! submission_date must match date in Description File
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $message = "";
  if ($db_name eq "cdev") {
    $submission_date = $dateToday;
  } elsif ($submission_date eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date required but missing;  --->[%s]\n", $tag_code_or_release_id, $submission_date;
  } elsif ($submission_date !~ /^\d\d\d\d\d\d\d\d$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date must be in YYYYMMDD format;  --->[%s]\n", $tag_code_or_release_id, $submission_date;
  } elsif (!(&isValidDate($submission_date))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $submission_date;
  } elsif (!(&isFutureDate($submission_date))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $submission_date;
  } elsif (($skip_expiredDate eq "N") && (!(isExpiredDate($submission_date, 30)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $submission_date;
  } elsif ($baseDateOfSubmission eq "") {
    $baseDateOfSubmission = $submission_date;
  } elsif (($skip_baseDate eq "N") && ($submission_date != $baseDateOfSubmission)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date not uniform (base date, submission_date);  --->[%s][%s]\n", $tag_code_or_release_id, $baseDateOfSubmission, $submission_date;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%% reporting_agency      %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($reporting_agency eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency required but missing;  --->[%s]\n", $tag_code_or_release_id, $reporting_agency;
  } elsif ($reporting_agency ne $agency) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency does not match agency entered;  --->[%s][%s]\n", $tag_code_or_release_id, $reporting_agency, $agency;
  } elsif (!($reporting_agencies{$reporting_agency})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency not recognized;  --->[%s]\n", $tag_code_or_release_id, $reporting_agency;
  } elsif ($baseAgencyCodeReporting eq "") {
    $baseAgencyCodeReporting = $reporting_agency;
  } elsif ($reporting_agency ne $baseAgencyCodeReporting) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency not uniform (base agency, reporting_agency);  --->[%s][%s]\n", $tag_code_or_release_id, $baseAgencyCodeReporting, $reporting_agency;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%% $release_agency        %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($release_agency eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  release_agency required but missing;  --->[%s]\n", $tag_code_or_release_id, $release_agency;
  } elsif (!($release_agencies{$release_agency})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  release_agency not recognized;  --->[%s]\n", $tag_code_or_release_id, $release_agency;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%  $coordinator      %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($coordinator eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  coordinator required but missing;  --->[%s]\n", $tag_code_or_release_id, $coordinator;
   } elsif (!($coordinators{$coordinator.$reporting_agency})) {
      $valid = 0;
      $error_cnt ++;
    printf "%12s; |ERR|  coordinator code not recognized for reporting agency;  --->[%s][%s]\n", $tag_code_or_release_id, $coordinator, $reporting_agency;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $tag_code_or_release_id %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $messge = "";
  if ($tag_code_or_release_id eq "") {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_code_or_release_id required but missing;  --->[%s]\n", $tag_code_or_release_id, $tag_code_or_release_id;
    next;
  } elsif ($tag_code_or_release_id =~ / /) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_code_or_release_id has embedded spaces;  --->[%s]\n", $tag_code_or_release_id, $tag_code_or_release_id;
  } elsif (&isAgencyMismatch($tag_code_or_release_id, $reporting_agency)) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code_or_release_id already reported by another agency;  --->[%s]\n", $tag_code_or_release_id,
$tag_code_or_release_id;
  } elsif ($record_code eq "N") {
    if (!(&isValidBangCode($tag_code_or_release_id))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code_or_release_id not valid or inconsistant with record_code;  --->[%s][%s]\n", $tag_code_or_release_id, $tag_code_or_release_id, $record_code;
    } elsif (!(&isMatchingCoordinator($tag_code_or_release_id, $coordinator))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code_or_release_id %s;  --->[%s][%s]\n", $tag_code_or_release_id, $message, $tag_code_or_release_id, $coordinator;
    } elsif ($tagCode_id{$tag_code_or_release_id}) {
      $unvalidated++;
      $error_cnt ++;
      delete $releases_validated{$tag_code_or_release_id};
      printf "%12s; |ERR|  tag_code_or_release_id duplicate id;  --->[%s]\n", $tag_code_or_release_id, $tag_code_or_release_id;
      next;
    } else {
      $tagCode_id{$tag_code_or_release_id} = 1;
    }
  } elsif ($record_code eq "T") {
    if (!(&isValidTagCode($tag_code_or_release_id))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code_or_release_id not valid or inconsistant with record_code;  --->[%s][%s]\n", $tag_code_or_release_id, $tag_code_or_release_id, $record_code;
    } elsif ($tagCode_id{$tag_code_or_release_id}) {
      $valid = 0;
      $error_cnt ++;
      delete $releases_validated{$tag_code_or_release_id};
      printf "%12s; |ERR|  tag_code_or_release_id duplicate id;  --->[%s]\n", $tag_code_or_release_id, $tag_code_or_release_id;
    }
  } else {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_code_or_release_id inconsistant with record_code;  --->[%s][%s]\n", $tag_code_or_release_id, $tag_code_or_release_id, $record_code;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $tag_type      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_type eq "") {
    if ($record_code eq "T") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_type required when record_code is 'T';  --->[%s][%s]\n", $tag_code_or_release_id, $tag_type, $record_code;
    }
  } elsif (!($tag_types{$tag_type})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type not recognized;  --->[%s]\n", $tag_code_or_release_id, $tag_type;
  } elsif (($tag_type eq "16") && ($record_code ne "N")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type inconsistant with record_code;  --->[%s]\n", $tag_code_or_release_id, $tag_type, $record_code;
  } elsif (($tag_type ne "16") && ($record_code eq "N")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type inconsistant with record_code;  --->[%s]\n", $tag_code_or_release_id, $tag_type, $record_code;
  } elsif (($tag_type eq "4") && ($tag_code_or_release_id ne "XX0500")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type X-ray binary, but tag_code_or_release_id not 'XX0500';  --->[%s]\n", $tag_code_or_release_id, $tag_type;
  } elsif (($tag_type eq "10") && (($first_sequential_number eq "") || ($last_sequential_number eq ""))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type Sequential 6-word binary, but sequential_number series ranges blank;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $tag_type, $first_sequential_number, $last_sequential_number;
  } elsif (($tag_type eq "15") || ($tag_type eq "3")) { 
    $tag_code_digits = length($tag_code_or_release_id); 
    if ($tag_code_digits < 10) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_type inconsistant with tag_code_or_release_id for number of recorded digits - should be 10 digits;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $tag_type, $tag_code_or_release_id, $tag_code_digits;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%% $first_sequential_number %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($first_sequential_number ne "") { 
    if (($tag_type ne "10") && ($tag_type ne "14")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_sequential_number must be blank for given tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $first_sequential_number, $tag_type;
    } elsif ($first_sequential_number !~ /^[+-]?\d{1,5}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_sequential_number must be numeric;  --->[%s]\n", $tag_code_or_release_id, $first_sequential_number;
    } elsif (($tag_type eq "10") && (($first_sequential_number < 0) || ($first_sequential_number > 16383))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_sequential_number must be in the range '0' thru '16383' for tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $first_sequential_number, $tag_type;
    } elsif (($tag_type eq "14") && (($first_sequential_number < 0) || ($first_sequential_number > 99999))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_sequential_number must be in the range '0' thru '99999' for tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $first_sequential_number, $tag_type;
    } elsif (($last_sequential_number ne "") && ($first_sequential_number > $last_sequential_number)) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_sequential_number can not be greater than last_sequential_number;  --->[%s][%s]\n", $tag_code_or_release_id, $first_sequential_number, $last_sequential_number;
    } 
  }
  
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $last_sequential_number %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($last_sequential_number ne "") { 
    if (($tag_type ne "10") && ($tag_type ne "14")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_sequential_number must be blank for given tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $last_sequential_number, $tag_type;
    } elsif ($last_sequential_number !~ /^[+-]?\d{1,5}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_sequential_number must be numeric;  --->[%s]\n", $tag_code_or_release_id, $last_sequential_number;
    } elsif (($tag_type eq "10") && (($last_sequential_number < 0) || ($last_sequential_number > 16383))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_sequential_number must be in the range '0' thru '16383' for tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $last_sequential_number, $tag_type;
    } elsif (($tag_type eq "14") && (($last_sequential_number < 0) || ($last_sequential_number > 99999))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_sequential_number must be in the range '0' thru '99999' for tag_type;  --->[%s][%s]\n", $tag_code_or_release_id, $last_sequential_number, $tag_type;
    } elsif (($first_sequential_number ne "") && ($last_sequential_number < $first_sequential_number)) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_sequential_number can not be less than first_sequential_number;  --->[%s][%s]\n", $tag_code_or_release_id, $last_sequential_number, $first_sequential_number;
    } 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%% $related_group_type      %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($related_group_type ne "") {
    if (!($related_group_types{$related_group_type})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  related_group_type not recognized;  --->[%s]\n", $tag_code_or_release_id, $related_group_type;
    }
  } elsif ($related_group_id ne "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  related_group_type required when related_group_id is present;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_type, $related_group_id;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $related_group_id %%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($related_group_id ne "") {
    if (length($related_group_id) > 15) {
       $valid = 0;
       $error_cnt ++;
       printf "%12s; |ERR|  related_group_id field exceeds maximum allowable field length of 15 characters;  --->[%s]\n", $tag_code_or_release_id, $related_group_id;
    } else {
      my $group_coordinator = substr($related_group_id,0,2);
      my $group_year = substr($related_group_id,2,4);
      if (!($tag_coordinators{$group_coordinator})) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  related_group_id 'coordinator' not recognized;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_id, $group_coordinator;
      } elsif ($group_year !~ /^\d\d\d\d$/) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  related_group_id 'year' must in 'YYYY' format;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_id, $group_year;
      } elsif ($group_year > $yearToday) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  related_group_id 'year' cannot be future year;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_id, $group_year;
      } elsif ($group_year < 1900) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  related_group_id 'year' out of range;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_id, $group_year;
      }
    }
  } elsif ($related_group_type ne "") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  related_group_id required when related_group_type is present;  --->[%s][%s]\n", $tag_code_or_release_id, $related_group_id, $related_group_type;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%% $species      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($species eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  species required but missing;  --->[%s]\n", $tag_code_or_release_id, $species;
  } elsif (!($species{$species})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  species not recognized;  --->[%s]\n", $tag_code_or_release_id, $species;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%% $run      %%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($run ne "") {
    if (!$runs{$run}) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  run not recognized;  --->[%s]\n", $tag_code_or_release_id, $run;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $brood_year      %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($brood_year eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  brood_year required but missing;  --->[%s]\n", $tag_code_or_release_id, $brood_year;
  } elsif (($midyear eq "Y") && (($brood_year < ($yearToday - 2)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  brood_year too old to be a mid-year release;  --->[%s]\n", $tag_code_or_release_id, $brood_year;
  } elsif ($brood_year !~ /^\d\d\d\d$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  brood_year must be numeric in YYYY format;  --->[%s]\n", $tag_code_or_release_id, $brood_year;
  } elsif ($brood_year < 1900) {
    $message_cnt ++;
    printf "%12s; |MSG|  brood_year out of range;  --->[%s]\n", $tag_code_or_release_id, $brood_year;
  } elsif ($brood_year > $yearToday) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  brood_year greater than this year;  --->[%s]\n", $tag_code_or_release_id, $brood_year;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $first_release_date %%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $message = "";
  $from_year = "";
  $from_month = "";
  $from_day = "";
  $from_date = "";
  if ($first_release_date eq "") {
      if ($study_integrity ne "D") {
        if (($midyear eq "N") || (($brood_year < ($yearToday - 2)))) {
          $valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  first_release_date required;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
        }
      }
#    }
  } elsif (($first_release_date !~ /^\d{8}$/) && ($first_release_date !~ /^\d{6}$/) && ($first_release_date !~ /^\d{4}$/)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  first_release_date must be in the format YYYYMMDD, YYYYMM, or YYYY;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
  } elsif ($first_release_date =~ /^\d{8}$/) {
    $from_date = $first_release_date;
    $from_year = substr($first_release_date,0,4);
    if (!(&isValidDate($first_release_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d8 %s;  --->[%s]\n", $tag_code_or_release_id, $message, $first_release_date;
    } elsif (!(&isFutureDate($first_release_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d8 %s;  --->[%s]\n", $tag_code_or_release_id, $message, $first_release_date;
    } elsif ($first_release_date lt "19000101") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d8 out of range;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
    } elsif ($from_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date (YYYY d8) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year;
    } elsif (($from_year == $brood_year) && ($record_code eq "T")) {
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date (YYYY d8) equals brood_year is unlikely for record_code, please review;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year, $record_code;
    }
  } elsif (($from_year,$from_month) = $first_release_date =~ /^(\d{4})(\d\d)$/) {
    $from_day = "01"; 
    $from_date = sprintf "%04d%02d%02d", $from_year, $from_month, $from_day;
    if (!(&isValidDate($from_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d6 %s;  --->[%s]\n", $tag_code_or_release_id, $message, $first_release_date;
    } elsif (($from_year > $yearToday) || (($from_year == $yearToday) && ($from_month > $monthToday))){
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d6 date greater than today;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
    } elsif ($first_release_date lt "190001") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d6 out of range;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
    } elsif ($from_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date_year (YYYY d6) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year;
#    } elsif ($from_year == $brood_year) {
    } elsif (($from_year == $brood_year) && ($record_code eq "T")){
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date_year (YYYY d6) equals brood_year is unlikely for record_code, please review;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year, $record_code;
    }
  } elsif (($from_year) = $first_release_date =~ /^(\d{4})$/) {
    $from_month = "01"; 
    $from_day = "01"; 
    $from_date = sprintf "%04d%02d%02d", $from_year, $from_month, $from_day;
    if (!(&isValidDate($from_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d4 %s;  --->[%s]\n", $tag_code_or_release_id, $message, $first_release_date;
    } elsif ($from_year > $yearToday) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d4 date greater than today;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
    } elsif ($first_release_date lt "1900") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  first_release_date d4 out of range;  --->[%s]\n", $tag_code_or_release_id, $first_release_date;
    } elsif ($from_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date_year (YYYY d4) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year;
    } elsif (($from_year == $brood_year) && ($record_code eq "T")) {
      $message_cnt ++;
      printf "%12s; |MSG|  first_release_date_year (YYYY d4) equals brood_year is unlikely for record_code, please review;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $first_release_date, $brood_year, $record_code;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $last_release_date %%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $message = "";
  $to_year = "";
  $to_month = "";
  $to_day = "";
  $to_date = "";
  if ($last_release_date eq "") {
      if ($study_integrity ne "D") {
        if (($midyear eq "N") || (($brood_year < ($yearToday - 2)))) {
          $valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  last_release_date required;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
        }
      }
  } elsif (($last_release_date !~ /^\d{8}$/) && ($last_release_date !~ /^\d{6}$/) && ($last_release_date !~ /^\d{4}$/)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  last_release_date must be in the format YYYYMMDD, YYYYMM, or YYYY;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
  } elsif ($last_release_date =~ /^\d{8}$/) {
    $to_date = $last_release_date;
    $to_year = substr($last_release_date,0,4);
    if (!(&isValidDate($last_release_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $last_release_date;
    } elsif (!(&isFutureDate($last_release_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $last_release_date;
    } elsif ($last_release_date lt "19000101") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date out of range;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
    } elsif ($to_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  last_release_date_year (YYYY) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $last_release_date, $brood_year;
    }
  } elsif (($to_year,$to_month) = $last_release_date =~ /^(\d{4})(\d\d)$/) {
    $to_day = "01"; 
    $to_date = sprintf "%04d%02d%02d", $to_year, $to_month, $to_day;
    if (!(&isValidDate($to_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $last_release_date ;
    } elsif (($to_year > $yearToday) || (($to_year == $yearToday) && ($to_month > $monthToday))){
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date date greater than today;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
    } elsif ($last_release_date lt "190001") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date out of range;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
    } elsif ($to_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  last_release_date_year (YYYY) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $last_release_date, $brood_year;
    }
  } elsif (($to_year) = $last_release_date =~ /^(\d{4})$/) {
    $to_month = "01"; 
    $to_day = "01"; 
    $to_date = sprintf "%04d%02d%02d", $to_year, $to_month, $to_day;
    if (!(&isValidDate($to_date))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date %s;  --->[%s]\n", $tag_code_or_release_id, $message, $last_release_date;
    } elsif ($to_year > $yearToday) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date date greater than today;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
    } elsif ($last_release_date lt "1900") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  last_release_date out of range;  --->[%s]\n", $tag_code_or_release_id, $last_release_date;
    } elsif ($to_year < $brood_year) {
      $message_cnt ++;
      printf "%12s; |MSG|  last_release_date_year (YYYY) less than brood_year;  --->[%s][%s]\n", $tag_code_or_release_id, $last_release_date, $brood_year;
    }
  }

  #%%%%% NOTE a longer from_date with the same YYYY and/or MM is greater than the to_date.
  if (($first_release_date ne "") && ($last_release_date ne "")) { 
    if (($last_release_date =~ /^\d{8}$/)) { 
      if (($from_date gt $to_date)) { 
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  first_release_date greater than last_release_date;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $last_release_date; 
      }
    } elsif (($last_release_date =~ /^\d{6}$/)) {
      if (($from_year gt $to_year) || (($from_year eq $to_year) && ($from_month gt $to_month))) { 
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  first_release_date greater than last_release_date;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $last_release_date,; 
      }
    } elsif (($last_release_date =~ /^\d{4}$/)) {
      if ($from_year gt $to_year) { 
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  first_release_date greater than last_release_date;  --->[%s][%s]\n", $tag_code_or_release_id, $first_release_date, $last_release_date; 
      }
    }
  }

  #%%%%% NOTE If tag code is a resubmission and species, brood_year, or first_release_date has changed, 
  #      Lookup the earliest status '1' recovery for the tag code to ensure any new value(s) will not 
  #      invalidate existing tag_status '1' recoveries.
  #  DLW - 20110527
  if ($from_date ne "") {
     $rl_first_date = $from_date;
  } else {
     $rl_first_date = $to_date;
  }
 
  if (($all_rc_tags{$tag_code_or_release_id})) {
    $k = 0;
    $ok_to_proceed_with_crosscheck = "Y";
    VERIFY_PROCEED: until ($rc_crosscheck_fields[$k][0] eq $tag_code_or_release_id)  {
      $k++;
      if ($k > $#rc_crosscheck_fields)  {
	$valid = 0;
	$error_cnt ++;
        printf "%12s; |ERR| A problem occured looking up the tag code in the rc_crosscheck_fields array. \n", $tag_code_or_release_id;
        printf "            The tag code may exist in the recovery table but failed to load in cross-checked array.\n";
        $ok_to_proceed_with_crosscheck = "N";
        last VERIFY_PROCEED;
      }
    }
    
    if ($ok_to_proceed_with_crosscheck eq "Y") {
       $rc_tagcode    = $rc_crosscheck_fields[$k][0];
       $rc_first_date = $rc_crosscheck_fields[$k][1];
      if ($rl_first_date > $rc_first_date) { 
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  first_release_date, rl_first_date after first existing rc_first_date.;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $first_release_date, $rl_first_date, $rc_first_date;
      } elsif (!($all_tags{$tag_code_or_release_id})) {
         $message_cnt ++;
         printf "%12s; |MSG|  Missing previous release when status '1' recoveries exist;  --->\n", $tag_code_or_release_id;
      } else {  
        $k = 0;
        VERIFY_PROCEED: until ($rl_crosscheck_fields[$k][0] eq $tag_code_or_release_id)  {
          $k++;
          if ($k > $#rl_crosscheck_fields)  {
	    $valid = 0;
	    $error_cnt ++;
            printf "%12s; |ERR|  Problem occurred during cross check of Tagcode in RC table. \n", $tag_code_or_release_id;
            printf "             Check to see if previous release was marked as Destroyed and a status 1 recovery exists. \n", $tag_code_or_release_id;
            $ok_to_proceed_with_crosscheck = "N";
            last VERIFY_PROCEED;
          }
        }
          if  ($ok_to_proceed_with_crosscheck eq "Y") {
          #$rl_tagcode    = $rl_crosscheck_fields[$k][0];
          $rl_species    = $rl_crosscheck_fields[$k][1];
          $rl_broodyear  = $rl_crosscheck_fields[$k][2];
          #$rl_rlyear     = $rl_crosscheck_fields[$k][3];
          #$rl_rlmonth    = $rl_crosscheck_fields[$k][4];
          #$rl_rlday      = $rl_crosscheck_fields[$k][5];
      
          if ($rl_species ne $species) { 
            $valid = 0;
            $error_cnt ++;
            printf "%12s; |ERR|  New species conflicts with existing species for existig validated recoveries;  --->[%s][%s]\n", $tag_code_or_release_id, $species, $rl_species;
          } elsif ($rl_broodyear ne $brood_year) { 
            $valid = 0;
            $error_cnt ++;
            printf "%12s; |ERR|  New brood_year conflicts with existing brood_year for existing validated recoveries;  --->[%s][%s]\n", $tag_code_or_release_id, $brood_year, $rl_broodyear;
          }  
          # $ok_to_proceed_with_crosscheck = "N";  # after crosscheck, set default value for next RL row
        }
      }
      # $ok_to_proceed_with_crosscheck = "N";  # after crosscheck, set default value for next RC row
    }
  }
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%% $release_location_code %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($release_location_code eq "") {
    if (($study_integrity ne "D") && ($midyear ne "Y"))  {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_location_code required if study_integrity is not 'D';  --->[%s][%s]\n", $tag_code_or_release_id, $release_location_code, $study_integrity;
    }
  } else {
    if ($release_location_code =~ / $/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_location_code should not contain trailing spaces;  --->[%s]\n", $tag_code_or_release_id, $release_location_code;
    } elsif (!(&location_exists($release_location_code, "4"))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_location_code not recognized;  --->[%s]\n", $tag_code_or_release_id, $release_location_code;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%% $hatchery_location_code %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($hatchery_location_code ne "") {
    if ($hatchery_location_code =~ / $/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  hatchery_location_code should not contain trailing spaces;  --->[%s]\n", $tag_code_or_release_id, $hatchery_location_code;
    } elsif (!(&location_exists($hatchery_location_code, "3"))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  hatchery_location_code not recognized;  --->[%s]\n", $tag_code_or_release_id, $hatchery_location_code;
    } elsif ($rearing_type =~ /[WM]/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  hatchery_location_code inconsistant with rearing_type;  --->[%s][%s]\n", $tag_code_or_release_id, $hatchery_location_code, $rearing_type;
    }
  } elsif ($rearing_type eq "H") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  hatchery_location_code inconsistant with rearing_type;  --->[%s][%s]\n", $tag_code_or_release_id, $hatchery_location_code, $rearing_type;
  }
    
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%% $stock_location_code %%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($stock_location_code ne "") {
    if ($stock_location_code =~ / $/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  stock_location_code should not contain trailing spaces;  --->[%s]\n", $tag_code_or_release_id, $stock_location_code;
    } elsif (!(&location_exists($stock_location_code, "5"))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  stock_location_code not recognized;  --->[%s]\n", $tag_code_or_release_id, $stock_location_code;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%% $release_stage %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($release_stage ne "") {
    if (!($release_stages{$release_stage})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_stage not recognized;  --->[%s]\n", $tag_code_or_release_id, $release_stage;
    } elsif (($release_stage eq "M") && ($comments eq "")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_stage 'M' requires comments;  --->[%s][%s]\n", $tag_code_or_release_id, $release_stage, $comments;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%% $rearing_type %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($rearing_type eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  rearing_type required but missing;  --->[%s]\n", $tag_code_or_release_id, $rearing_type;
  } elsif (!($rearing_types{$rearing_type})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  rearing_type not recognized;  --->[%s]\n", $tag_code_or_release_id, $rearing_type;
  } elsif (($rearing_type eq "H") && ($hatchery_location_code eq "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  rearing_type requires hatchery_location_code be present;  --->[%s][%s]\n", $tag_code_or_release_id, $rearing_type, $hatchery_location_code;
  } elsif (($rearing_type =~ /^(W|M)$/) && (($hatchery_location_code ne "") || ($release_strategy ne ""))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  rearing_type requires hatchery_location_code and release_strategy be absent;  --->[%s][%s][%s]\n", $tag_code_or_release_id, $rearing_type, $hatchery_location_code, $release_strategy;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%% $study_type %%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($study_type ne "") {
    if (!($study_types{$study_type})) { 
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  study_type not recognized;  --->[%s]\n", $tag_code_or_release_id, $study_type;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $release_strategy %%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($release_strategy ne "") {
    if (!($release_strategies{$release_strategy})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_strategy not recognized;  --->[%s]\n", $tag_code_or_release_id, $release_strategy;
    } elsif ($rearing_type =~ /^(W|M)$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  release_strategy must be absent when rearing_type is 'W' or 'M';  --->[%s][%s]\n", $tag_code_or_release_id, $release_strategy, $rearing_type;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%% $avg_weight  %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($avg_weight ne "") {
    if ($avg_weight !~ /^((\d{1,4}(\.\d{0,2})?)|(\.\d{1,2}))$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  avg_weight must be blank or numeric in the range: '0.01' thru '9999.99';  --->[%s]\n", $tag_code_or_release_id, $avg_weight; 
    } elsif ($avg_weight < 0.01) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  avg_weight must be blank or numeric in the range: '0.01' thru '9999.99';  --->[%s]\n", $tag_code_or_release_id, $avg_weight; 
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%% $avg_length  %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($avg_length ne "") {
    if ($avg_length !~ /^\d{1,6}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  avg_length must be blank or numeric in the range '1' thru '999999';  --->[%s]\n", $tag_code_or_release_id, $avg_length;
    } elsif ($avg_length < 1) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  avg_length must be blank or numeric in the range '1' thru '999999';  --->[%s]\n", $tag_code_or_release_id, $avg_length;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $study_integrity %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($study_integrity ne "") {
    if (!($study_integrities{$study_integrity})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  study_integrity not recognized;  --->[%s]\n", $tag_code_or_release_id, $study_integrity;
    } elsif ($study_integrity eq "W") {
      if (($comments eq "") || ($comments =~ /^\W+$/) || ($comments =~ /^\s+$/)) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  study_integrity of 'W' require comments be present;  --->[%s][%s]\n", $tag_code_or_release_id, $study_integrity, $comments;
      }
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%% Mark Codes - Record Code Specific Checks %%%%% 
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($record_code eq "N") {
    if (($cwt_1st_mark ne "") || ($cwt_1st_mark_count ne "") || ($cwt_2nd_mark ne "") || ($cwt_2nd_mark_count ne "")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  record_code requires that cwt_1st_mark, cwt_1st_mark_count, cwt_2nd_mark and cwt_2nd_mark_count be blank;  --->[%s][%s][%s][%s][%s]\n", $tag_code_or_release_id, $record_code, $cwt_1st_mark, $cwt_1st_mark_count, $cwt_2nd_mark, $cwt_2nd_mark_count;
    }
    if (($non_cwt_1st_mark eq "") || ($non_cwt_1st_mark_count eq "")) {
      if ($study_integrity ne "D") {
        if (($midyear eq "N") || (($brood_year < ($yearToday - 2)))) {
          $valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  non_cwt_1st_mark and non_cwt_1st_mark_count must be present when record_code is 'N';  --->[%s][%s][%s]\n", $tag_code_or_release_id, $non_cwt_1st_mark, $non_cwt_1st_mark_count, $record_code;
        }
      }
    }
  } else {
    if (($cwt_1st_mark eq "") || ($cwt_1st_mark_count eq "")) {
      if ($study_integrity ne "D") {
        if (($midyear eq "N") || (($brood_year < ($yearToday - 2)))) {
          $valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  cwt_1st_mark and cwt_1st_mark_count must be present when record_code is 'T';  --->[%s][%s][%s]\n", $tag_code_or_release_id, $cwt_1st_mark, $cwt_1st_mark_count, $record_code;
        }
      }
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%  Mark Codes Value Checks %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  &check_mark ($tag_code_or_release_id, "cwt_1st_mark", $cwt_1st_mark, $cwt_1st_mark_count, 'cwt', $brood_year, $study_integrity);
  if ($return_errors > 0) {
    $valid = 0;
    $error_cnt = $error_cnt + $return_errors;
  }

  &check_mark ($tag_code_or_release_id, "cwt_2nd_mark", $cwt_2nd_mark, $cwt_2nd_mark_count, 'cwt', $brood_year, $study_integrity);
  if ($return_errors > 0) {
    $valid = 0;
    $error_cnt = $error_cnt + $return_errors;
  }

  &check_mark ($tag_code_or_release_id, "non_cwt_1st_mark", $non_cwt_1st_mark, $non_cwt_1st_mark_count, 'non', $brood_year, $study_integrity);
  if ($return_errors > 0) {
    $valid = 0;
    $error_cnt = $error_cnt + $return_errors;
  }
  
  &check_mark ($tag_code_or_release_id, "non_cwt_2nd_mark", $non_cwt_2nd_mark, $non_cwt_2nd_mark_count, 'non', $brood_year, $study_integrity);
  if ($return_errors > 0) {
    $valid = 0;
    $error_cnt = $error_cnt + $return_errors;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%  Mark Codes Combined Value Checks %%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($cwt_2nd_mark ne "") {
    if ($cwt_2nd_mark eq $cwt_1st_mark) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  cwt_2nd_mark must not contain the same value as cwt_1st_mark;  --->[%s][%s]\n", $tag_code_or_release_id, $cwt_2nd_mark, $cwt_1st_mark;
    }
  }

  if ($cwt_2nd_mark_count ne "") {
    if (($cwt_1st_mark_count eq "") || ($cwt_1st_mark_count eq "0")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  cwt_2nd_mark_count must be absent when cwt_1st_mark_count is absent or zero;  --->[%s][%s]\n", $tag_code_or_release_id, $cwt_2nd_mark_count, $cwt_1st_mark_count;
    }
  }

  if ($non_cwt_2nd_mark ne "") {
    if ($non_cwt_2nd_mark eq $non_cwt_1st_mark) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  non_cwt_2nd_mark must not contain the same value as non_cwt_1st_mark;  --->[%s][%s]\n", $tag_code_or_release_id, $non_cwt_2nd_mark, $non_cwt_1st_mark;
    }
  }

  if ($non_cwt_2nd_mark_count ne "") {
    if ($non_cwt_1st_mark_count eq "") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  non_cwt_2nd_mark_count must be absent when non_cwt_1st_mark_count is absent;  --->[%s][%s]\n", $tag_code_or_release_id, $non_cwt_2nd_mark_count, $non_cwt_1st_mark_count;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%% $counting_method        %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($counting_method ne "") {
    if (!($counting_methods{$counting_method})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  counting_method not recognized;  --->[%s]\n", $tag_code_or_release_id, $counting_method;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $tag_loss_rate    %%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_loss_rate ne "") {
    if (($record_code eq "N") && ($tag_type ne "16")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_rate must be blank when record_code is 'N' and tag_type is not '16';  --->[%s][%s][%s]\n", $tag_code_or_release_id, $tag_loss_rate, $record_code, $tag_type;
    } elsif (($tag_loss_rate !~ /^((\d(\.\d{0,4})?)|(\.\d{1,4}))$/) || (($tag_loss_rate < 0) || ($tag_loss_rate > 1))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_rate must be numeric in the range '0' thru '1';  --->[%s]\n", $tag_code_or_release_id, $tag_loss_rate;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $tag_loss_days     %%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_loss_days ne "") {
    if (($record_code eq "N") && ($tag_type ne "16")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_days must be blank when record_code is 'N' and tag_type is not '16';  --->[%s][%s][%s]\n", $tag_code_or_release_id, $tag_loss_days, $record_code, $tag_type;
    } elsif ($tag_loss_days !~ /^\d{1,3}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_days must be numeric in the range '0' thru '999';  --->[%s]\n", $tag_code_or_release_id, $tag_loss_days;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%% $tag_loss_sample_size %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_loss_sample_size ne "") {
    if (($record_code eq "N") && ($tag_type ne "16")) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_sample_size must be blank when record_code is 'N' and tag_type is not '16';  --->[%s][%s][%s]\n", $tag_code_or_release_id, $tag_loss_sample_size, $record_code, $tag_type;
    } elsif ($tag_loss_sample_size !~ /^\d{1,5}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_loss_sample_size must be numeric in the range '0' thru '99999';  --->[%s]\n", $tag_code_or_release_id, $tag_loss_sample_size;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%% $tag_reused      %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_reused ne "") {
    if ($record_code eq "N") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_reused must be blank when record_code is 'N';  --->[%s][%s]\n", $tag_code_or_release_id, $tag_reused, $record_code;
    } elsif ($tag_reused ne "Y") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_reused must be 'Y' or Blank;  --->[%s]\n", $tag_code_or_release_id, $tag_reused;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% $comments      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  # see study_integrity
  # see release_stage 
   if ($comments ne "") {
     if (length($comments) > 200) {
       $valid = 0;
       $error_cnt ++;
       printf "%12s; |ERR|  comments field exceeds maximum allowable field length of 200 character;  --->[%s]\n", $tag_code_or_release_id, $comments;
     }
   }

   if ($comments ne "") {
     if ($comments =~ /.*[^\x00-\x7F]+./) {
       $valid = 0;
       $error_cnt ++;
       printf "%12s; |ERR|  comments field should not include non-ascii characters;  --->[%s]\n", $tag_code_or_release_id, $comments;
     }
   }
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%% End Validation %%%%%%%%%%%%%%%%%%%%%%%%%% 
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($valid == 1) {
    $validated++; 
    $releases_validated{$tag_code_or_release_id} = 1;
  } else {
    $unvalidated++; 
  } 

  # -----------------------------------------------------------------
  # Assign selected columns to array for analysis of Related Group Id
  # -----------------------------------------------------------------
  if (($related_group_type eq "D") && ($related_group_id ne ""))  {
    $rl_rgid_newset[$j][0]  = $tag_code_or_release_id;
    $rl_rgid_newset[$j][1]  = $submission_date;
    $rl_rgid_newset[$j][2]  = $reporting_agency;
    $rl_rgid_newset[$j][3]  = $related_group_type;
    $rl_rgid_newset[$j][4]  = $related_group_id;
    $rl_rgid_newset[$j][5]  = $species;
    $rl_rgid_newset[$j][6]  = $brood_year;
    $rl_rgid_newset[$j][7]  = $cwt_1st_mark;
    $rl_rgid_newset[$j][8]  = $cwt_2nd_mark;
    $rl_rgid_newset[$j][9]  = $cwt_1st_mark_count;
    $rl_rgid_newset[$j][10] = $cwt_2nd_mark_count;
    $j++;
  }
}

# Analyze Related Group Id for DIT type releases from incoming dataset compared with rows on-file to
# find if error or warning condition exists.
($error_cnt, $message_cnt, $validated, $unvalidated, %releases_validated)  = 
	rl_rgid_analyze($error_cnt, $message_cnt, $validated, $unvalidated, %releases_validated);

# Verify total csv records in equals total records processed
my $total_run_cnt = $validated + $unvalidated;
printf(scalar(localtime) . ": Total csv records - $total_csv_cnt\n");
printf(scalar(localtime) . ": Total val records - $total_run_cnt\n");

if ($total_csv_cnt != $total_run_cnt) {
  $valid = 0;
  &error_exit("rl_validate","Total csv count DOES NOT EQUAL total val count, validation halted");
}

print "Result: $validated rows validated, $unvalidated rows not validated, $error_cnt total errors, $message_cnt total messages.\n";
&load_log("v", $validated + $unvalidated, $validated);
printf(scalar(localtime) . ": EXITING rl_validate.pm \n");
printf("\n");
if ($unvalidated == 0) {
  printf(scalar(localtime) . ": Please submit a description file for this VALIDATED dataset  \n");
  printf(scalar(localtime) . " \n");
  return 1;  # validation was successful
} else {
  return 0; # validation was unsuccessful
}

}

sub check_mark {
  $return_errors = 0; 
  my ($tag_code, $field_name, $mark, $mark_count, $mark_type, $brood_year, $study_integrity) = @_;

  if (($mark ne "") && (!(&mark_exists($mark)))) {
    $return_errors ++;
    printf "%12s; |ERR|  %s not recognized;  --->[%s]\n", $tag_code, $field_name, $mark;
  } elsif (($brood_year > 1994) && (substr($mark,0,1) eq "9")) {
    $return_errors ++;
    printf "%12s; |ERR|  %s must not begin with '9' if brood year gt '1994';  --->[%s][%s]\n", $tag_code, $field_name, $mark, $brood_year;
  }

  if (($midyear eq "N") || (($brood_year < ($yearToday - 2)))) {
    if ($study_integrity ne "D") {
      if ((($mark eq "") && ($mark_count ne "")) || (($mark ne "") && ($mark_count eq ""))) { 
        $return_errors ++;
        printf "%12s; |ERR|  %s and mark_count must both be present or blank;  --->[%s][%s]\n", $tag_code, $field_name, $mark, $mark_count;
      }
    }
    if (($mark_count ne "") && ($mark_type eq "cwt") && ($mark_count !~ /^\d{1,8}$/)) {
      $return_errors ++;
      printf "%12s; |ERR|  %s mark_count must be numeric in the range '0' thru '99999999';  --->[%s]\n", $tag_code, $field_name, $mark_count;
    } elsif (($mark_count ne "") && ($mark_type eq "non") && ($mark_count !~ /^\d{1,9}$/)) {
      $return_errors ++;
      printf "%12s; |ERR|  %s mark_count must be numeric in the range '0' thru '999999999';  --->[%s]\n", $tag_code, $field_name, $mark_count;
    }
  }
}
