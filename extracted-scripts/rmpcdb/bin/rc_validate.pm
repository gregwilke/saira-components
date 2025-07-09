return 1;

# *****************************************************************************
# Name:          rc_validate.pm
# Description:   pre-validate RC recovery csv file prior to database load
# *****************************************************************************
# Program History for Format Ver 4.2
# INT  DATE      Comments
# ---  ----      -------
# DLW  20230628  Begin modifiacations for Format Ver 4.2
#                Added $TESTING, $skip_expireDate & $skip_baseDate checks
#
#                PRODUCTION NOTES:  Enable submission_date checks
#                                   Enable weight limit checks
#
# DLW  20250513  Add non-ascii character check
# -----------------------------------------------------------------------------
# Program History prior to Format Ver 4.2
# INT  DATE      Comments
# ---  --------  --------
# DLW  20030716  Ported from Onco System 
# JRL  20040225  Added logic to check against tagged releases table as follows:
#	1) Check tag_code against all tags to flag that tag_code must actually
#	be present in RL table for tag_status '1' (even if tag_code appears correct);
#	2) Cross-check recovery against corresponding release record to see if
#	species and recovery date match properly. (Note that brood/age checks can
#	be added later if desired using array rl_crosscheck_fields).
# JRL  20040427  Fixed problem w/RC Date ERR message
# DLW  20040622  Changed $from_year, $from_month, $from_day to $tmp_year, $tmp_month,
#       $tmp_day.   A full recovery_date is not required therfore the tmp variables
#       are used to fill in the incomplete portions of the date for validation and 
#       comparison routines.  Be sure to rei-clear them if they are reused.
# DLW  20050430  Uncommented Gear validation check to start validating gears.
# DLW  20050902  Added Validation logic for use of BLANK or agency BLANK wire.
#                Validate tag_type and tag_status with blank wire.
#                Warn for use of coordinator code followed by all zeros in tag_code
# DLW  20051013  Added message for length greater than 1600 millimeters 
# DLW  20051107  Created agency_codes table in cwt_defns for validation BLANK wire.
# DLW  20060215  Added message for length greater than 1300 millimeters for species 
#                Not Equal to '1' (Chinook).
# DLW  20080229  Add field length validation checks.
# DLW  20090331  Modifications for Ver 4.1 Validation
# DLW  20100128  Added submission_date check for full 8 digit date
#                and limited isExpiredDate to 30 days
# DLW  20100302  Added Description request comment for VALIDATED data set
# JRL  20110211  Added function filter_csv to run before doing CSV check 
# JRL  20110926  In Cross-check code section, changed error_exit code to data error
#		 condition; clarified wording of condition.
# DLW  20111104  Added creation of temp file in /var/autosubmit/ for auto merge process
# JRL  20111201  In Cross-check code section, fixed problem with failure to terminate
#                loop when tagcode not found in array rl_crosscheck_fields (in special
#                cases, ex where a status 1 recovery is reported of destroyed rl group)
# DLW  20130204  Changed MSG to ERR for Coho > 1600mm &  Chinook > 1300mm
# DLW  20140530  Added length check to sample_site field
# DLW  20140616  Modified sequential_number check to limit field length to 5 characters
#                Reviewed checks on each field to ensure that field lengths are not
#                exceeded then causing the load process to potential fail during merge.
# DLW  20140818  Replace DBI::CSV routine with Text::CSV to avoid records dropped from
#                processing when double quotes '"' are present within a field.
# DLW  20150514  Added check for number of tag_code digits for tag_type
#                '15' or '3' - should be 10 digits instead of 6.
# DLW  20150519  Added tag_type to crosscheck section Updated ERR messages for cross-check 
#                fields to be consistent with standardized error message format and display
#                of database field names.
# DLW  20151103  Changed order of fields in "recovery tag_type must match release tag_type"
#                error messages to match order in which referenced in message.
# DLW  20151109  CDFO removed from release tag_type validation cross-check error test per
#                email request by Kathy Fraser on 20151106 to allow 1993-2014 recoveries
#                submitted on 20151104 to pass validation without corrections to the CDFO
#                recovery datasets to match reported release tag_type (release tag_types
#                were verified by NMT on 20151105 and any necessary corrections to releases
#                were made by release agencies CRFC, FWS and YAKA prior to this modification)
# DLW  20160517  Only check tag length for 1/2 length tags (tag_type 3 and 15) 
#                when tag_status = '1'.  Allows tag_type for unreadable and lost tags.
# -----------------------------------------------------------------------------
$| = 1;
sub rc_validate {

  #TESTING variables
  my $TESTING             = "N";     # "Y" for testing
  my $skip_expiredDate    = "N";     # "Y" to skip isExpiredDate check
  my $skip_baseDate       = "N";     # "Y" to skip baseDateOfSubmission check

  my $error_cnt   = 0;
  my $message_cnt = 0;
  my $validated   = 0;
  my $unvalidated = 0;
  my $baseRunYear = "";
  my $baseDateOfSubmission = "";
  my $baseAgencyCodeReporting = "";
  my %recoveryCode_id;
  my $tmp_year  = "";         #Be sure to reclear if variable is reused.
  my $tmp_month = "";         #Be sure to reclear if variable is reused.
  my $tmp_day   = "";         #Be sure to reclear if variable is reused.
  my $tmp_date  = "";         #Be sure to reclear if variable is reused. 
  my $ok_to_proceed_with_crosscheck = 0;
  my $record_count = 0;
  my $data_count = 0;

  # Print header for log file
  printf(scalar(localtime) . ": STARTING rc_validate.pm \n");

  # Capture todays date to subsitute with submission_date for cdev testing 
  $dateToday = sprintf "%04d%02d%02d", sub {($_[5]+1900, $_[4]+1, $_[3])}->(localtime);
  printf(scalar(localtime) . ": Date Today is $dateToday \n");

  # Check CSV file format
  if (!(&csv_file_valid("$uvalpath/$std_file_name", 41))) {
    $valid = 0;
    &error_exit("rc_validate","Invalid CSV file format, no validation performed");
  }

  # Check for non-ascii characters
  if (!(&csv_check_ascii("$uvalpath/$std_file_name"))) {
    $valid = 0;
    &error_exit("rc_validate","Non-ASCII characters in file, no validation performed");
  }

  printf(scalar(localtime) . ": VALIDATING recovery records.... \n");
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
        &error_exit("rc_validate","CSV error on record $record_count - $error");
    }

#  # OPTIONAL print record number when TESTING
#  if ($TESTING eq "Y") {
#     printf "Processing Record Number ;  --->[%s]\n", $record_count;
#  }

  my ($record_code, 
  $format_version, 
  $submission_date,
  $reporting_agency,
  $sampling_agency,
  $recovery_id,
  $species,
  $run_year,
  $recovery_date,
  $recovery_date_type,
  $period_type,
  $period,
  $fishery,
  $gear,
  $adclip_selective_fishery,
  $estimation_level,
  $recovery_location_code,
  $sampling_site,
  $recorded_mark,
  $sex,
  $weight,
  $weight_code,
  $weight_type,
  $length,
  $length_code,
  $length_type,
  $detection_method,
  $tag_status,
  $tag_code,
  $tag_type,
  $sequential_number,
  $sequential_column_number,
  $sequential_row_number,
  $catch_sample_id,
  $sample_type,
  $sampled_maturity,
  $sampled_run,
  $sampled_length_range,
  $sampled_sex,
  $sampled_mark,
  $number_cwt_estimated) = $csv->fields ();

  # Skip Header Record
  if ($record_count == 1) {
    next;   # Skip HEADER record and read next for DATA record
  } else {
    $data_count++;
  }

#  # OPTIONAL print record number when TESTING
#  if ($TESTING eq "Y") {
#    printf "Processing Record Number ;  --->[%s]\n", $record_count;
#  }

  # do field validations
  my $valid = 1;		# set $valid = 0 if any field validations fail
  my $rc_date_valid = 1;	# set $rc_date_valid = 0 if recovery_date fails
  my $tag_code_valid = 1;	# set $tag_code_valid = 0 if tag_code fails
  my $species_valid = 1;	# set $species_valid = 0 if species fails
  my $tag_type_valid = 1;	# set $tag_type_valid = 0 if tag_type fails

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%1 %%%%%%%%%%%%%%%%%%%% record_code  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($record_code eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  record_code required but missing;  --->[%s]\n", $recovery_id, $record_code; 
  } elsif ($record_code ne "R") {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  record_code must be 'R';  --->[%s]\n", $recovery_id, $record_code; 
    next;
  }  

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%2 %%%%%%%%%%%%%%%%%%%%% $format_version %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($format_version eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  format_version required but missing;  --->[%s]\n", $recovery_id, $format_version; 
  } elsif (!($format_version =~ /^$current_format/)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  format_version must be '%s';  --->[%s]\n", $recovery_id, $current_format, $format_version;
  }
    
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%3 %%%%%%%%%%%%%%%%%%% $submission_date  %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%% NOTE! submission_date must match date in Description File
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $message = "";
  if ($db_name eq "cdev") {
    $submission_date = $dateToday;
  } elsif ($submission_date eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date required but missing;  --->[%s]\n", $recovery_id, $submission_date;
  } elsif ($submission_date !~ /^\d\d\d\d\d\d\d\d$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date must be in YYYYMMDD format;  --->[%s]\n", $recovery_id, $submission_date;
  } elsif (!(&isValidDate($submission_date))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $recovery_id, $message, $submission_date;
  } elsif (!(&isFutureDate($submission_date))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $recovery_id, $message, $submission_date;
  } elsif (($skip_expiredDate eq "N") && (!(isExpiredDate($submission_date, 30)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date %s;  --->[%s]\n", $recovery_id, $message, $submission_date;
  } elsif ($baseDateOfSubmission eq "") {
    $baseDateOfSubmission = $submission_date;
  } elsif (($skip_baseDate eq "N") && ($submission_date != $baseDateOfSubmission)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  submission_date not uniform (base date, submission_date);  --->[%s][%s]\n", $recovery_id, $baseDateOfSubmission, $submission_date;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%4 %%%%%%%%%%%%%%%% reporting_agency      %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($reporting_agency eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency required but missing;  --->[%s]\n", $recovery_id, $reporting_agency;
  } elsif ($reporting_agency ne $agency) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency does not match agency entered;  --->[%s][%s]\n", $recovery_id, $reporting_agency, $agency;
  } elsif (!($reporting_agencies{$reporting_agency})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency not recognized;  --->[%s]\n", $recovery_id, $reporting_agency;
  } elsif ($baseAgencyCodeReporting eq "") {
    $baseAgencyCodeReporting = $reporting_agency;
  } elsif ($reporting_agency ne $baseAgencyCodeReporting) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  reporting_agency not uniform (base agency, reporting_agency);  --->[%s][%s]\n", $recovery_id, $baseAgencyCodeReporting, $reporting_agency;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%5 %%%%%%%%%%%%%%%% sampling_agency       %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampling_agency ne "") {
    if (!($sampling_agencies{$sampling_agency})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sampling_agency not recognized;  --->[%s]\n", $recovery_id, $sampling_agency;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%6 %%%%%%%%%%%%%%%%%%%% $recovery_id            %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $messge = "";
  if ($recovery_id eq "") {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_id required but missing;  --->[%s]\n", $recovery_id, $recovery_id;
    next;
  } elsif ($recovery_id =~ / /) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_id has embedded spaces;  --->[%s]\n", $recovery_id, $recovery_id;
  } elsif ($recoveryCode_id{$recovery_id}) {
    $unvalidated++;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_id duplicate id;  --->[%s]\n", $recovery_id, $recovery_id;
    next;
  } elsif (length($recovery_id) > 10) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_id field exceeds maximum field length of 10 characters;  --->[%s]\n", $recovery_id, $recovery_id;
  } else {
    $recoveryCode_id{$recovery_id} = 1;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%7 %%%%%%%%%%%%%%%%%%%%%% $species      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($species eq "") {
    $valid = 0;
    $species_valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  species required but missing;  --->[%s]\n", $recovery_id, $species;
  } elsif (!($species{$species})) {
    $valid = 0;
    $species_valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  species not recognized;  --->[%s]\n", $recovery_id, $species;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%8 %%%%%%%%%%%%%%%%%%%%% $run_year        %%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($run_year eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  run_year required but missing;  --->[%s]\n", $recovery_id, $run_year;
  } elsif ($run_year !~ /^\d\d\d\d$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  run_year must be numeric in 'YYYY' format;  --->[%s]\n", $recovery_id, $run_year;
  } elsif ($run_year < 1972) {
    $message_cnt ++;
    printf "%12s; |MSG|  run_year out of range;  --->[%s]\n", $recovery_id, $run_year;
  } elsif ($run_year > $yearToday) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  run_year greater than this year;  --->[%s]\n", $recovery_id, $run_year;
  } elsif ($run_year ne $year) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  run_year does not match year entered;  --->[%s][%s]\n", $recovery_id, $run_year, $year;
  } elsif ($baseRunYear eq "") {
    $baseRunYear = $year;
  } elsif ($run_year ne $baseRunYear) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  run_year not uniform (base year, run_year);  --->[%s][%s]\n", $recovery_id, $baseRunYear, $run_year;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%9 %%%%%%%%%%%%%%%%%%%% $recovery_date      %%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $tmp_year  = "";         #Be sure to reclear if variable is reused.
  $tmp_month = "";         #Be sure to reclear if variable is reused.
  $tmp_day   = "";         #Be sure to reclear if variable is reused.
  $tmp_date  = "";         #Be sure to reclear if variable is reused. 
  $message      = "";

  if ($recovery_date eq "") {
    $valid = 0;
    $rc_date_valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_date required but missing;  --->[%s]\n", $recovery_id, $recovery_date;
  } elsif ($recovery_date =~ /^\d\d\d\d\d\d\d\d$/) {
    $tmp_date = $recovery_date;
    if (!(&isValidDate($recovery_date))) {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date %s;  --->[%s]\n", $recovery_id, $message, $recovery_date;
    } elsif (!(&isFutureDate($recovery_date))) {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date %s;  --->[%s]\n", $recovery_id, $message, $recovery_date;
    } elsif ($recovery_date lt "19700101") {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date out of range;  --->[%s]\n", $recovery_id, $recovery_date;
    }
  } elsif (($tmp_year,$tmp_month) = $recovery_date =~ /^(\d\d\d\d)(\d\d)$/) {
    $tmp_day = "01";
    $tmp_date = sprintf "%04d%02d%02d", $tmp_year, $tmp_month, $tmp_day;
    if (!(&isValidDate($tmp_date))) {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date %s;  --->[%s]\n", $recovery_id, $message, $recovery_date;
    } elsif (($tmp_year > $yearToday) || (($tmp_year == $yearToday) && ($tmp_month > $monthToday))){
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date date greater than today;  --->[%s]\n", $recovery_id, $recovery_date;
    } elsif ($recovery_date lt "197001") {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date out of range;  --->[%s]\n", $recovery_id, $recovery_date;
    }
  } elsif (($tmp_year) = $recovery_date =~ /^(\d\d\d\d)$/) {
    $tmp_month = "01";
    $tmp_day = "01";
    $tmp_date = sprintf "%04d%02d%02d", $tmp_year, $tmp_month, $tmp_day;
    if (!(&isValidDate($tmp_date))) {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date %s;  --->[%s]\n", $recovery_id, $message, $recovery_date;
    } elsif ($tmp_year > $yearToday) {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date date greater than today;  --->[%s]\n", $recovery_id, $recovery_date;
    } elsif ($recovery_date lt "1970") {
      $valid = 0;
      $rc_date_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date out of range;  --->[%s]\n", $recovery_id, $recovery_date;
    }
  } else {
    $valid = 0;
    $rc_date_valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_date must be in the format 'YYYYMMDD', 'YYYYMM', or 'YYYY';  --->[%s]\n", $recovery_id,
$recovery_date;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%10 %%%%%%%%%%%%%%%%% $recovery_date_type     %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($recovery_date_type ne "") {
    if (!($recovery_date_types{$recovery_date_type})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  recovery_date_type not recognized;  --->[%s]\n", $recovery_id, $recovery_date_type;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%11 %%%%%%%%%%%%%%%%% $period_type            %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($period_type eq "") {
    if ($period ne "") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  period_type required when period is present;  --->[%s][%s]\n", $recovery_id, $period_type, $period;
    } elsif ($sample_type =~ /(1|2|4|6)/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  period_type required with this sample_type;  --->[%s][%s]\n", $recovery_id, $period_type, $sample_type;
    }
  } elsif (!($sampling_period_types{$period_type})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period_type not recognized;  --->[%s]\n", $recovery_id, $period_type;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%12 %%%%%%%%%%%%%%%%% $period                 %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($period eq "") {
    if ($period_type ne "") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  period required when period_type is present;  --->[%s][%s]\n", $recovery_id, $period, $period_type;
    }
  } elsif ($period !~ /^\d\d$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be numeric with two digits;  --->[%s]\n", $recovery_id, $period;
  } elsif (($period < 01) || ($period > 54)) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period not recognized;  --->[%s]\n", $recovery_id, $period;
  } elsif (($period_type eq "1") && ($period ne "01")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be '01' when period_type is '1';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  } elsif (($period_type eq "2") && (($period < 01) || ($period > 26))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be in range 01 - 26 when period_type is '2';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  } elsif (($period_type eq "3") && (($period < 01) || ($period > 24))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be in range '01' thru '24' when period_type is '3';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  } elsif (($period_type =~ /(4|5)/) && (($period < 01) || ($period > 12))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be in range '01' thru '12' when period_type is '4' or '5';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  } elsif (($period_type eq "8") && (($period < 01) || ($period > 04))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be in range '01' thru  '04' when period_type is '8';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  } elsif (($period_type =~ /(6|7|10|11)/) && (($period < 01) || ($period > 54))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  period must be in range '01' thru '54' when period_type is '6, 7, 10, or 11';  --->[%s][%s]\n", $recovery_id, $period, $period_type;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%13 %%%%%%%%%%%%%%%%% $fishery                %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($fishery eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  fishery required but missing;  --->[%s]\n", $recovery_id, $fishery;
  } elsif (!($fisheries{$fishery})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  fishery not recognized;  --->[%s]\n", $recovery_id, $fishery;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%14 %%%%%%%%%%%%%%%%% $gear                   %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($gear ne "") {
    if (!($gears{$fishery.$reporting_agency.$gear})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  gear not recognized for fishery and reporting_agency;  --->[%s][%s][%s]\n", $recovery_id, $gear, $fishery, $reporting_agency;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%15 %%%%%%%%%%%% $adclip_selective_fishery      %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($adclip_selective_fishery ne "") {
    if (!($adclip_selective_code{$adclip_selective_fishery})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  adclip_selective_fishery not recognized;  --->[%s]\n", $recovery_id, $adclip_selective_fishery;
    }
  } elsif ($run_year > 2007) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  adclip_selective_fishery must be present when run_year > '2007';  --->[%s][%s]\n", $recovery_id, $adclip_selective_fishery, $run_year;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%16 %%%%%%%%%%%%%%%%% $estimation_level        %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($estimation_level eq "") {
    if ((&isNumeric($number_cwt_estimated) && ($number_cwt_estimated > 0))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  estimation_level must be present when estimatied_number is greater than 0;  --->[%s][%s]\n", $recovery_id, $estimation_level, $number_cwt_estimated;
    }
  } elsif (!($estimation_levels{$estimation_level})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  estimation_level not recognized;  --->[%s]\n", $recovery_id, $estimation_level;
  }
 
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%17 %%%%%%%%%%% $recovery_location_code       %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($recovery_location_code eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_location_code required but missing;  --->[%s]\n", $recovery_id, $recovery_location_code;
  } elsif ($recovery_location_code =~ / $/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_location_code should not contain trailing spaces;  --->[%s]\n", $recovery_id, $recovery_location_code;
  } elsif (!(&location_exists($recovery_location_code, "1"))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recovery_location_code not recognized;  --->[%s]\n", $recovery_id, $recovery_location_code;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%18 %%%%%%%%%%%%%%%%% $sampling_site          %%%%%%%%%%%%%%%%%%%%
  # Agency in-house codes for Port of landing, hatchery, etc.
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampling_site ne "") {
    if (length($sampling_site) > 4) {
       $valid = 0;
       $error_cnt ++;
       printf "%12s; |ERR|  sampling_site field exceeds maximum allowable field length of 4 characters;  --->[%s]\n", $recovery_id, $sampling_site;
    }
  }
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%19 %%%%%%%%%%%%%%%%% $recorded_mark          %%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($recorded_mark eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recorded_mark required but missing;  --->[%s]\n", $recovery_id, $recorded_mark;
  } elsif (!(&mark_exists($recorded_mark))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  recorded_mark not recognized;  --->[%s]\n", $recovery_id, $recorded_mark;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%20 %%%%%%%%%%%%%%%%%%%%%% $sex         %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sex ne "") {
    if ($sex !~ /^(M|F)$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sex must be 'M', 'F', or absent;  --->[%s]\n", $recovery_id, $sex;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%21 %%%%%%%%%%%%%%%%%% $weight          %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($weight ne "") {
    if ($weight !~ /^((\d{1,2}(\.\d{0,2})?)|(\.\d{1,2}))$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight must be absent or numeric with no more than two decimal places to the right of the decimal point;  --->[%s]\n", $recovery_id, $weight; 
    } elsif ($weight < .01) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight must be absent or numeric in the range '0.01' thru '99.99' with two digits to the right of the decimal point;  --->[%s]\n", $recovery_id, $weight; 
    } elsif ($weight > 59.99) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight must be absent or numeric in the range '0.01' thru '59.99'kg;  --->[%s][%s]\n", $recovery_id, $weight, $species;
    } elsif (($weight > 27.49) && (($species ne "1") && ($species ne " 1"))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight must be absent or numeric in the range '0.01' thru '27.49'kg for species other than '1';  --->[%s][%s]\n", $recovery_id, $weight, $species;
    }
  } elsif (($weight_code ne "") || ($weight_type ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  weight required when weight_code or weight_type present;  --->[%s][%s][%s]\n", $recovery_id, $weight, $weight_code, $weight_type; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%22 %%%%%%%%%%%%%%%%%% $weight_code     %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($weight_code ne "") {
    if (!($weight_codes{$weight_code})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight_code not recognized;  --->[%s]\n", $recovery_id, $weight_code; 
    }
  } elsif (($weight ne "") || ($weight_type ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  weight_code required when weight or weight_type present;  --->[%s][%s][%s]\n", $recovery_id, $weight_code, $weight, $weight_type; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%23 %%%%%%%%%%%%%%%%%% $weight_type     %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($weight_type ne "") {
    if (!($weight_types{$weight_type})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  weight_type not recognized;  --->[%s]\n", $recovery_id, $weight_type; 
    }
  } elsif (($weight ne "") || ($weight_code ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  weight_type required when weight or weight_code present;  --->[%s][%s][%s]\n", $recovery_id, $weight_type, $weight, $weight_code; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%24 %%%%%%%%%%%%%%%%%%%%%% $length      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($length ne "") {
    if ($length !~ /^\d{1,4}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length must be absent or numeric in the range '1' thru '9999';  --->[%s]\n", $recovery_id, $length;
    } elsif ($length < 1) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length must be absent or numeric in the range '1' thru '9999';  --->[%s]\n", $recovery_id, $length;
    } elsif ($length > 1600) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length greater than 1600mm is not reasonable;  --->[%s]\n", $recovery_id, $length;
    } elsif (($length > 1300) && (($species ne "1") && ($species ne " 1"))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length greater than 1300mm is not reasonable for species;  --->[%s][%s]\n", $recovery_id, $length, $species;
    }
  } elsif (($length_code ne "") || ($length_type ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  length required when length_code or length_type present;  --->[%s][%s][%s]\n", $recovery_id, $length, $length_code, $length_type; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%25 %%%%%%%%%%%%%%%%%% $length_code     %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($length_code ne "") {
    if (!($length_codes{$length_code})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length_code not recognized;  --->[%s]\n", $recovery_id, $length_code; 
    }
  } elsif (($length ne "") || ($length_type ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  length_code required when length or length_type present;  --->[%s][%s][%s]\n", $recovery_id, $length_code, $length, $length_type; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%26 %%%%%%%%%%%%%%%%%%% $length_type    %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($length_type ne "") {
    if (!($length_types{$length_type})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  length_type not recognized;  --->[%s]\n", $recovery_id, $length_type; 
    }
  } elsif (($length ne "") || ($length_code ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  length_type required when length or length_code present;  --->[%s][%s][%s]\n", $recovery_id, $length_type, $length, $length_code; 
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%27 %%%%%%%%%%%%%%%%%% $detection_method     %%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($detection_method eq "") {
    if ($catch_sample_id ne "") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  detection_method required when catch_sample_id present;  --->[%s][%s]\n", $recovery_id, $detection_method, $catch_sample_id;
    }
  } elsif (!($cwt_detection_methods{$detection_method})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  detection_method not recognized;  --->[%s]\n", $recovery_id, $detection_method;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%28 %%%%%%%%%%%%%%%%%% $tag_status      %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_status eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_status required but missing;  --->[%s]\n", $recovery_id, $tag_status;
  } elsif (!($tag_statuses{$tag_status})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_status not recognized;  --->[%s]\n", $recovery_id, $tag_status;
  } 

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%29 %%%%%%%%%%%%%%%%%% $tag_code        %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_code ne "") {
    if ($tag_status eq "1") {
      if (!isValidTagCode($tag_code)) {
        $valid = 0;
        $tag_code_valid = 0;
        $error_cnt ++;
      	printf "%12s; |ERR|  tag_code must be valid CWT for tag_status '1';  --->[%s][%s]\n", $recovery_id, $tag_code, $tag_status;
      } elsif (!($all_tags{$tag_code})) {
          $valid = 0;
          $tag_code_valid = 0;
          $error_cnt ++;
      	  printf "%12s; |ERR|  recovery tag_code must be present in releases for tag_status '1';  --->[%s][%s]\n", $recovery_id, $tag_code, $tag_status;
      } elsif (substr($tag_code, 2) == 0) {
          $message_cnt ++;
          printf "%12s; |MSG|  tag_code with coordinator then all zeros may be BLANK wire;  --->[%s]\n", $recovery_id, $tag_code;
      }
    } elsif ($tag_status eq "9") {
      if ((!($tag_code =~ /^BLANK$/)) && (!($tag_code =~ /^\d\dBLANK$/))) {
        $valid = 0;
        $tag_code_valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  tag_code invalid with tag_status for BLANK wire;  --->[%s][%s]\n", $recovery_id, $tag_code, $tag_status;
      } elsif ($tag_code =~ /^\d\dBLANK$/) {
        my $agencyCode = substr($tag_code, 0, 2);
        if (!($agency_codes{$agencyCode})) {
          $valid = 0;
          $tag_code_valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  tag_code's Agency Wire Prefix invalid for BLANK wire;  --->[%s][%s]\n", $recovery_id, $tag_code, $agencyCode;
        }
      }
    } elsif ($tag_code =~ /BLANK/) {
      $valid = 0;
      $tag_code_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code requires a tag_status of '9' for BLANK wire;  --->[%s][%s]\n", $recovery_id, $tag_code, $tag_status;
    } elsif ($tag_code =~ / /) {
      $valid = 0;
      $tag_code_valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_code has embedded spaces;  --->[%s]\n", $recovery_id, $tag_code;
    } 
  } elsif ($tag_status =~ /^(1|9)$/) {
    $valid = 0;
    $tag_code_valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_code required for reported tag_status;  --->[%s][%s]\n", $recovery_id, $tag_code, $tag_status;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%30 %%%%%%%%%%%%%%%%%% $tag_type        %%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($tag_type eq "") {
    if ($tag_status =~ /^(1|9)$/) {
      $tag_type_valid = 0;
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  tag_type required for reported tag_status;  --->[%s][%s]\n", $recovery_id, $tag_type, $tag_status;
    }
  } elsif (!($tag_types{$tag_type})) {
    $tag_type_valid = 0;
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type not recognized;  --->[%s]\n", $recovery_id, $tag_type;
  } elsif (($tag_type ne "16") && ($tag_status eq "9")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type inconsistent with tag_status;  --->[%s][%s]\n", $recovery_id, $tag_type, $tag_status;
  } elsif (($tag_type eq "16") && ($tag_status ne "9")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  tag_type inconsistent with tag_status;  --->[%s][%s]\n", $recovery_id, $tag_type, $tag_status;
  } elsif (($tag_type eq "15") || ($tag_type eq "3")) {
    if ($tag_status eq "1") {
      $tag_code_digits = length($tag_code);
      if ($tag_code_digits < 10) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  tag_type inconsistent with tag_code for number of recorded digits - should be 10 digits;  --->[%s][%s][%s]\n", $recovery_id, $tag_type, $tag_code, $tag_code_digits;
      }
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%31 %%%%%%%%%%%%%%%% $sequential_number     %%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sequential_number ne "") {
    if ($tag_type !~ /^(10|14)$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_number must be absent unless tag_type is '10' or '14';  --->[%s][%s]\n", $recovery_id, $sequential_number, $tag_type;
    } elsif ($sequential_number !~ /^\d{0,5}$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_number must be numeric up to 5 characters;  --->[%s]\n", $recovery_id, $sequential_number;
    }
  }
      
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%32 %%%%%%%%%%%%% $sequential_column_number      %%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sequential_column_number ne "") {
    if ($tag_type ne "10") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_column_number must be absent unless tag_type is '10';  --->[%s][%s]\n", $recovery_id, $sequential_column_number, $tag_type;
    } elsif (($sequential_column_number !~ /^\d{0,3}$/) || (($sequential_column_number < 0) || ($sequential_column_number > 127))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_column_number must be numeric in the range '0' thru '127';  --->[%s]\n", $recovery_id, $sequential_column_number;
    }
  }
      
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%33 %%%%%%%%%%%%%% $sequential_row_number     %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sequential_row_number ne "") {
    if ($tag_type ne "10") {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_row_number must be absent unless tag_type is '10';  --->[%s][%s]\n", $recovery_id, $sequential_row_number, $tag_type;
    } elsif (($sequential_row_number !~ /^\d{0,3}$/) || (($sequential_row_number < 0) || ($sequential_row_number > 127))) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sequential_row_number must be numeric in the range '0' thru '127';  --->[%s]\n", $recovery_id, $sequential_row_number;
    }
  }
      
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%34 %%%%%%%%%%%%%%%%%% $catch_sample_id        %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($catch_sample_id ne "") {
    if ($catch_sample_id =~ / /) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  catch_sample_id must not include imbedded spaces;  --->[%s]\n", $recovery_id, $catch_sample_id;
      } elsif (length($catch_sample_id) > 10) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  catch_sample_id field exceeds maximum field length of 10 characters;  --->[%s]\n", $recovery_id, $catch_sample_id;
      }
  } elsif ($sample_type =~ /^(1|2|4|6)$/) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  catch_sample_id required for this sample_type;  --->[%s][%s]\n", $recovery_id, $catch_sample_id, $sample_type;
  }
    
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%35 %%%%%%%%%%%%%%%%%%%% $sample_type          %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sample_type eq "") {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sample_type required but missing;  --->[%s]\n", $recovery_id, $sample_type;
  } elsif (!($sample_types{$sample_type})) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sample_type not recognized;  --->[%s]\n", $recovery_id, $sample_type;
  } elsif (($sample_type =~ /^(2|3)$/) && ((&isNumeric($number_cwt_estimated) && ($number_cwt_estimated == 0)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sample_type requires number_cwt_estimated to be absent or greater than '0';  --->[%s][%s]\n", $recovery_id, $sample_type, $number_cwt_estimated;
  } elsif (($sample_type =~ /^(4)$/) && ($number_cwt_estimated ne "")) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sample_type requires number_cwt_estimated to be absent;  --->[%s][%s]\n", $recovery_id, $sample_type, $number_cwt_estimated;
  } elsif (($sample_type =~ /^(5)$/) && ((&isNumeric($number_cwt_estimated) && ($number_cwt_estimated != 0)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sample_type requires number_cwt_estimated to be '0';  --->[%s][%s]\n", $recovery_id, $sample_type, $number_cwt_estimated;
  } elsif (($sample_type =~ /^(7)$/) && ((&isNumeric($number_cwt_estimated) && ($number_cwt_estimated != 1)))) {
    $message_cnt ++;
    printf "%12s; |MSG|  sample_type requires number_cwt_estimated to be '1';  --->[%s][%s]\n", $recovery_id, $sample_type, $number_cwt_estimated;
  }
 
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%36 %%%%%%%%%%%%%%%% $sampled_maturity         %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampled_maturity ne "") {
    if (!($maturity_classes{$sampled_maturity})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sampled_maturity not recognized;  --->[%s]\n", $recovery_id, $sampled_maturity;
    }
  } 

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%37 %%%%%%%%%%%%%%%%%%% $sampled_run     %%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampled_run ne "") {
    if (!($runs{$sampled_run})) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sampled_run not recognized;  --->[%s]\n", $recovery_id, $sampled_run;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%38 %%%%%%%%%%%%%%%%% $sampled_length_range    %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampled_length_range ne "") {
    if ($sampled_length_range =~ /^\d\d\d\d\d\d\d\d$/) {
      my $lengthFirst = substr($sampled_length_range, 0, 4);
      my $lengthLast = substr($sampled_length_range, 4,4);
      if ($lengthFirst > $lengthLast) {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  sampled_length_range lower value greater than upper value;  --->[%s][%s]\n", $recovery_id, $lengthFirst, $lengthLast;
      }
    } else {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sampled_length_range must be numeric in the range '00000000' thru '99999999' if present;  --->[%s]\n", $recovery_id, $sampled_length_range;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%39 %%%%%%%%%%%%%%%%%% $sampled_sex            %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($sampled_sex ne "") {
    if ($sampled_sex !~ /^(M|F)$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  sampled_sex must be 'M', 'F', or absent;  --->[%s]\n", $recovery_id, $sampled_sex;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%40 %%%%%%%%%%%%%%%%%% $sampled_mark           %%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if (($sampled_mark ne "") && (!(&mark_exists($sampled_mark)))) {
    $valid = 0;
    $error_cnt ++;
    printf "%12s; |ERR|  sampled_mark not recognized;  --->[%s]\n", $recovery_id, $sampled_mark;
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%41 %%%%%%%%%%%%%%%% $number_cwt_estimated      %%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if ($number_cwt_estimated ne "") {
    if ($number_cwt_estimated !~ /^((\d+(\.\d{0,2})?)|(\.\d{1,2}))$/) {
      $valid = 0;
      $error_cnt ++;
      printf "%12s; |ERR|  number_cwt_estimated must be numeric in the range '0' thru '99999.99' with two digits to the right of the decimal point;  --->[%s]\n", $recovery_id, $number_cwt_estimated;
    } elsif (($catch_sample_id eq "")  && ($number_cwt_estimated > 0)){
      $message_cnt ++;
      printf "%12s; |MSG|  catch_sample_id should be present when number_cwt_estimated > 0;  --->[%s][%s]\n", $recovery_id, $catch_sample_id, $number_cwt_estimated;
    }
  }

  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%    Cross-check Recovery record with Releases table    %%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  $tmp_year  = "";         #Be sure to reclear if variable is reused.
  $tmp_month = "";         #Be sure to reclear if variable is reused.
  $tmp_day   = "";         #Be sure to reclear if variable is reused.
  $tmp_date  = "";         #Be sure to reclear if variable is reused. 

  if ($tag_code_valid && $tag_status eq "1")  {
    $ok_to_proceed_with_crosscheck = 1;
    $k = 0;
    VERIFY_PROCEED:  until ($rl_crosscheck_fields[$k][0] eq $tag_code)  {
      $k++;
      if ($k > $#rl_crosscheck_fields)  {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  A problem has been identified with this recovery having tag_code [%s];\n", $recovery_id, $tag_code;
        printf "                     The tag_code cannot be cross-checked in the RL table.\n";
        printf "                     RL Study Integrity may indicate destroyed [D] release group.\n";
        $ok_to_proceed_with_crosscheck = 0;
        last VERIFY_PROCEED;
      }
    }

    if ($ok_to_proceed_with_crosscheck)  {
      #$rl_tagcode    = $rl_crosscheck_fields[$k][0];
      $rl_species    = $rl_crosscheck_fields[$k][1];
      #$rl_broodyear  = $rl_crosscheck_fields[$k][2];
      $rl_rlyear     = $rl_crosscheck_fields[$k][3];
      $rl_rlmonth    = $rl_crosscheck_fields[$k][4];
      $rl_rlday      = $rl_crosscheck_fields[$k][5];
      $rl_tagtype    = $rl_crosscheck_fields[$k][6];

      if ($species_valid && ($species ne $rl_species))  {
        $valid = 0;
        $error_cnt ++;
        printf "%12s; |ERR|  recovery species must match release species for tag_code; ---> [%s][%s][%s]\n", $recovery_id, $rl_species, $species, $tag_code;
      }
      
      #DLW - CDFO removed from release cross-check ERR test - See History Section for 20151109
      if ($tag_type_valid && ($tag_type ne $rl_tagtype)) {
        if (($rl_tagtype eq "15") ||
           ($rl_tagtype eq "3") ||
           ($tag_type eq "15") ||
           ($tag_type eq "3")) {
          if ($reporting_agency eq "CDFO") {
            $message_cnt ++;
            printf "%12s; |MSG|  recovery tag_type should match release tag_type for tag_code (with 1/2 length tags); ---> [%s][%s][%s]\n", $recovery_id, $tag_type, $rl_tagtype, $tag_code;
          } else {
            #$valid = 0;
            #$error_cnt ++;
            #printf "%12s; |ERR|  recovery tag_type must match release tag_type for tag_code (with 1/2 length tags); ---> [%s][%s][%s]\n", $recovery_id, $tag_type, $rl_tagtype, $tag_code;
            $message_cnt ++;
            printf "%12s; |MSG|  recovery tag_type should match release tag_type for tag_code (with 1/2 length tags); ---> [%s][%s][%s]\n", $recovery_id, $tag_type, $rl_tagtype, $tag_code;
          }
        } else {
          $message_cnt ++;
          printf "%12s; |MSG|  recovery tag_type should match release tag_type for tag_code; ---> [%s][%s][%s]\n", $recovery_id, $tag_type, $rl_tagtype, $tag_code;
        }
      }

      if ($rc_date_valid)  {
        if ($recovery_date =~ /^\d\d\d\d\d\d\d\d$/)  {
          ($tmp_year, $tmp_month, $tmp_day) = $recovery_date =~ /^(\d\d\d\d)(\d\d)(\d\d)$/;
        } elsif ($recovery_date =~ /^\d\d\d\d\d\d$/)  {
          ($tmp_year, $tmp_month) = $recovery_date =~ /^(\d\d\d\d)(\d\d)$/;
        } else  {
          ($tmp_year) = $recovery_date =~ /^(\d\d\d\d)$/;
        }

        if ($tmp_year < $rl_rlyear)  {
          $valid = 0;
          $rc_date_valid = 0;
          $error_cnt ++;
          printf "%12s; |ERR|  recovery_date earlier than year of release for tag_code;  --->[%s][%s][%s]\n", $recovery_id, $tmp_year, $rl_rlyear, $tag_code;
        } elsif ($tmp_year == $rl_rlyear)  {
          if ($tmp_month ne "") {
            if ($tmp_month < $rl_rlmonth)  {
              $valid = 0;
              $rc_date_valid = 0;
              $error_cnt ++;
            printf "%12s; |ERR|  recovery_date earlier than month of release for tag_code;  --->[%s][%s][%s]\n", $recovery_id, $tmp_month, $rl_rlmonth, $tag_code;
            } elsif ($tmp_month == $rl_rlmonth)  {
              if ($tmp_day ne "") {
                if ($tmp_day < $rl_rlday)  {
                  $valid = 0;
                  $rc_date_valid = 0;
                  $error_cnt ++;
                  printf "%12s; |ERR|  recovery_date earlier than day of release for tag_code;  --->[%s][%s][%s]\n", $recovery_id, $tmp_day, $rl_rlday, $tag_code;
                }
              }
            }
          }
        }
      }
      $ok_to_proceed_with_crosscheck = 0;  # after crosscheck, set default value for next RC row
    }
  }
  #%%%%%%%%%%%%%%%%%%%%%%%% End Validation %%%%%%%%%%%%%%%%%%%%%%%%%% 
  if ($valid == 1) {
    $validated++; 
  } else {
    $unvalidated++; 
  } 
}

# Verify total csv records in equals total records processed
my $total_run_cnt = $validated + $unvalidated;
printf(scalar(localtime) . ": Total csv records - $total_csv_cnt\n");
printf(scalar(localtime) . ": Total val records - $total_run_cnt\n");

if ($total_csv_cnt != $total_run_cnt) {
  $valid = 0;
  &error_exit("rc_validate","Total csv count DOES NOT EQUAL total val count, validation halted");
}

print "Result: $validated rows validated, $unvalidated rows not validated, $error_cnt total errors, $message_cnt total messages.\n";
&load_log("v", $validated + $unvalidated, $validated);
printf(scalar(localtime) . ": EXITING rc_validate.pm \n");
printf("\n");
if ($unvalidated == 0) {
  printf(scalar(localtime) . ": Please submit a description file for this VALIDATED dataset  \n");
  printf(scalar(localtime) . " \n");
  system("touch /var/autosubmit/rc_merge");
  return 1;  # validation was successful
} else {
  return 0; # validation was unsuccessful
}

}
