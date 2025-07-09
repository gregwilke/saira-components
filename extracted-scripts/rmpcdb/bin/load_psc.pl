#!/usr/local/bin/perl -w

# *****************************************************************************
# Name:          load_psc.pl
# Description:   mainline for load_psc program.  Calls stage, validate and move 
#                functions based on arguments supplied on the command line.           
#******************************************************************************
# Program History for Format Ver 4.2
# INT  DATE      Comments
# ---  -------   ---------
# DLW  20230628  Begin modifications for Format Ver 4.2
# DLW  20230628  Change data type table names with 041 to 042
#                Remove 041 from system processing table names and indexes
#                Update translation module names to indicate format version
#                Remove references to retired "ce" data type
#                Added $TESTING check
#
# -------------------------------------------------------------------
# Program History prior to Format Ver 4.2
# INT  DATE      Comments
# ---  --------  --------
# DLW  20030716  Coppied from Onco System
# JRL  20040225  Added module: get_rl_fields
# DLW  20050606  Added bkdev as a valid database option 
# DLW  20060112  Updated db_name to full database name cpro.psmfc.org to
#                work with new install of Oracle 10g
# JRL  20071002  Modified processing of RL dataset to allow full dataset load
#		 with row archive.  Load and move is denied if any errors
#		 found.  See flag 'fullset'.
# DLW  20090324  Modifications for Ver 4.1 Validation (Replaced all occurances 
#                of "4.0" with "4.1"
# JRL  20090410  Modifications for Ver 4.1 Validation: installed new module
#		 (rl_rgid_analyze) for validation of RL /related_group_id 
# DLW  20090623  Modifications to inclued translation programs as modules
# DLW  20090706  Updated dd_translate.pl & ce_translate.pl to perl modules 
# JRL  20090923  Assign of var $tran_message, syntax adjusted
# DLW  20110602  Call get_rl_fields and new get_rc_fields when processing
#                releases.
# DLW  20110830  Added new module for date formats "get_time_formats.pm",
#                append timestamp to user input file once processed.
# DLW  20120629  Replaced rename of file after PASS or FAIL with sudo
#                for rmpc in append_user_input routine
# DLW  20140609  Added processing field to load_log_041 and load_dates_041
# DLW  20140814  Add use Text::CSV;
#
# ---------------  2015 Oracle to Postgres Database Conversion  -------------  
#
# DLW  20150910  Modifications for Oracle to Postgres Database Conversion 
#                include changes to environment variable, database references,
#                SQL functions & some possible logic flow where necessary.
#                NOTE - Translation sections NOT currently used and NOT updated!  
#                       Re-evaluate when new format version is introduced.
#                       CE Datatype retired by PSC and NO LONGER Valid!! 
# DLW  20160115 Updated STAGING section.  Replaced system cp with dos2unix move.  
#               Standardizing files to unix/linux file formats for linux system 
#               commants.  cwt_defns.pm csv_file_valid sub expects a unix file 
#               for unix chomp command to work.  This change is associated with 
#               new loop in cwt_defns.pm csv_file_valid sub to check field by 
#               field for imbedded double quotes within the fields causing 
#               pgloader in ??_load.pm module(s) to skip records with imbedded 
#               quotes within fields without warning or notification.
#
#----------  2024 Migr to Ubuntu OS 24.04 and Postgres V16 Database -----------
# JRL  20240924  Minor syntax change in function append_user_input().
# JRL  20241105  Disabled 'chown' in function append_user_input().
#******************************************************************************

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  DRIVER  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

$| = 1;              #flushes the log buffer so output can be seen quicker

use lib $ENV{RMPCDB_BIN};
use DBI;
use date_time_formats;
use cwt_defns;
use cs_translate_to_042;
use cs_validate;
use cs_load;
use dd_translate_to_042;
use dd_validate;
use dd_load;
use lc_translate_to_042;
use lc_validate;
use lc_load;
use lc_refresh;
use rc_translate_to_042;
use rc_validate;
use rl_translate_to_042;
use rl_validate;
use rl_load;
use date_valid;
use number_valid;
use tag_analyze;
use get_rl_fields;
use get_rc_fields;
use rl_rgid_analyze;
use Date::Manip qw(ParseDate UnixDate);
use Date::Calc qw(Delta_Days);
use Text::ParseWords qw(quotewords);
use Text::CSV_XS;
use Text::CSV;

&Setup_Environment();

# Validating number of parameters
if ($#ARGV != 11) {
  printf("usage: load_psc.pl db_name           file_type agency year trans stage val move midyr fullset format file_name\n");
  printf("ex:    load_psc.pl rpro              cs        ADFW   2000   N     Y    Y   Y     N      N     4.2   /home/rmis/up/cs_ADFG_2000.csv\n");
  printf("\n");
  printf("Note: To refresh the Data Status pages you can run load_psc.pl with all flags\n");
  printf("      set to N. This will repopulate desc_status with summarized data from\n");
  printf("      descriptions_042 and will repopulate load_dates with summarized data\n");
  printf("      from load_log. This is only necessary if you manually change data in\n");
  printf("      descriptions_042 or load_log to correct the Data Status pages\n");
  exit(1);
}

# Assign global variables from parameter list @ARGV
$db_name     = $ARGV[0];
$file_type   = $ARGV[1];
$agency      = $ARGV[2];
$year        = $ARGV[3];
$translate   = $ARGV[4];
$stage       = $ARGV[5];
$validate    = $ARGV[6];
$move        = $ARGV[7];
$midyear     = $ARGV[8];
$fullset     = $ARGV[9];
$fmt_version = $ARGV[10];
$file_name   = $ARGV[11];

$file_type   = lc($file_type);
$agency      = uc($agency);
$stage       = uc($stage);
$validate    = uc($validate);
$move        = uc($move);
$midyear     = uc($midyear);
$fullset     = uc($fullset);

$input_file_name = $file_name;

# Construct standardized file name
$std_file_name = $file_type . "_" . $agency . "_" . $year . ".csv";
$pgloader_log    = "load_psc_" . $file_type . "_" . $agency . "_" . $year . ".llog";

# Print header for validation log file
printf(scalar(localtime) . ": Starting load_psc\n");
printf("db_name          = %s\n", $db_name);
printf("file_type        = %s\n", $file_type);
printf("agency           = %s\n", $agency);
printf("year             = %s\n", $year);
printf("translate        = %s\n", $translate);
printf("stage            = %s\n", $stage);
printf("validate         = %s\n", $validate);
printf("move             = %s\n", $move);
printf("midyear          = %s\n", $midyear);
printf("fullset          = %s\n", $fullset);
printf("fmt_version      = %s\n", $fmt_version);
printf("file_name        = %s\n", $file_name);
printf("std_file_name    = %s\n", $std_file_name);
printf("unvalidated_dir  = %s\n", $uvalpath);
printf("validated_dir    = %s\n", $valpath);
printf("log_dir          = %s\n", $logpath);

$valid = "Y";
$val_status = "";

# Validating the db_name parameters
if (($db_name ne "rpro") && ($db_name ne "rrep") && ($db_name ne "rdev1") && ($db_name ne "rdev2")&& ($db_name ne "rdev3")) {
    printf("Parameter error: db_name not recognized [%s]\n", $db_name);
    $valid = "N";
}

# Validating the file_type and year parameters
if ($file_type eq "cs" || $file_type eq "rc") {
  if ($year !~ /^\d{4}$/) {
    printf("Parameter error: valid year required for this file_type [%s][%s]\n", $year, $file_type);
    $valid = "N";
  } elsif ($year < 1950) {
    printf("Parameter error: year must be greater than or equal to 1950\n");
    exit(1);
  } elsif ($year >= 2050) {
    printf("Parameter error: year must be less than 2050\n");
    $valid = "N";
  }
} elsif ($file_type eq "dd" || $file_type eq "lc" || $file_type eq "rl") {
  $year = lc($year);
  if ($year ne "none") {
    printf("Parameter error: year must be 'none' for this file_type [%s][%s]\n", $year, $file_type);
    $valid = "N";
  }
} else {
  printf("Parameter error: file_type not recognized [%s]\n", $file_type);
  $valid = "N";
}

# Validating the agency parameter
if ($agency !~ /^[A-Z\-]{1,10}$/) {
  printf("Parameter error: agency format not recognized [%s]\n", $agency);
  $valid = "N";
}

# Validating the translate, stage, validate, move and midyear parameters
if ($translate !~ /^(Y|N)$/) {
  printf("Parameter error: invalid translate flag [%s]\n", $translate);
  exit(1);
}
if ($stage !~ /^(Y|N)$/) {
  printf("Parameter error: invalid stage flag [%s]\n", $stage);
  exit(1);
}
if ($validate !~ /^(Y|N)$/) {
  printf("Parameter error: invalid validate flag [%s]\n", $validate);
  exit(1);
}
if ($move !~ /^(Y|N)$/) {
  printf("Parameter error: invalid move flag [%s]\n", $move);
  exit(1);
}
if ($midyear !~ /^(Y|N)$/) {
  printf("Parameter error: invalid midyear flag [%s]\n", $midyear);
  exit(1);
}
if ($fullset !~ /^(Y|N)$/) {
  printf("Parameter error: invalid fullset flag [%s]\n", $fullset);
  exit(1);
}

# Set $processing variable for load_dates
$processing = "NONE";
if ($file_type eq "rl") {
  if ($midyear eq "Y" && $fullset eq "Y") {
    printf("Parameter error: invalid midyear and fullset flags [%s] [%s]\n", $midyear, $fullset);
    exit(1);
  } elsif ($midyear eq "N" && $fullset eq "N") {
    $processing = "PARTIAL";
  } elsif ($midyear eq "Y") {
    $processing = "PRELIM";
  } elsif ($fullset eq "Y") {
    $processing = "FULLSET";
  }
} elsif ($midyear eq "Y" || $fullset eq "Y") {
  printf("Parameter error: invalid midyear or fullset flag [%s] [%s]\n", $midyear, $fullset);
  exit(1);
}

printf("processing       = %s\n", $processing);
# printf(scalar(localtime) . ": VALIDATION special processing [%s].... \n", $processing);

# Validating the fmt_version parameter
if ($fmt_version ne $current_format) {
  printf("Parameter error: invalid fmt_version [%s]\n", $current_format);
  exit(1);
}

# Validating the file_name parameter
if ($file_name ne "none" && !-e "$file_name") {
  printf("Parameter error: file_name does not exist [%s]\n", $file_name);
  exit(1);
}

if ($valid eq "N") {
  exit(1);
}

# Translate here.  No need to connect to DB if translation fails. 
$translate_ok = 0;
if ($translate eq "Y") { 
  $translate_ok = &translate();
  if ($translate_ok) { 
    $file_name = $to_file_name;
    printf("file_name        = %s\n", $file_name);
  } else {
    exit(1);
  }
}

# Connect to the database
printf(scalar(localtime) . ": Connecting to $db_name database\n\n");
$dbh = DBI->connect("dbi:Pg:dbname=".$db_name ,$user ,$passwd, { RaiseError => 1, AutoCommit => 0 })
  or die "Can't open $db_name database: $DBI::errstr";
$dbh->commit();

# Validating the agency parameter
$sth = $dbh->prepare("
  SELECT COUNT(*)
  FROM   agencies
  WHERE  agency = ?
  AND    reporting_agency = 'Y'")
  or &error_exit("agencies1", $dbh->errstr);
$sth->execute($agency)
  or &error_exit("agencies2", $sth->errstr);
$row_count = $sth->fetchrow_array;
$sth->finish();
if ($row_count == 0) {
  &error_exit("agencies3", "Parameter error: agency must exist in agencies table and must have reporting_agency = 'Y'");
}

# Check admin table to see if another load_psc job is running for this file_type
$sth = $dbh->prepare("
  SELECT running
  FROM   admin_042
  WHERE  data_key = " . $dbh->quote($file_type))
  or &error_exit("admin1",$dbh->errstr);
$sth->execute()
  or &error_exit("admin2",$sth->errstr);
$flag = $sth->fetchrow_array;
$sth->finish();

## added check for TESTING
if ($TESTING eq "N") {
  if ($flag eq "Y") {
    &error_exit("admin3","Another " . $file_type . " job is running");
  } else {
    # set running flag so no other job of this type can run concurrently
    $dbh->do("
      UPDATE admin_042
      SET    staged = 'N', running = 'Y'
      WHERE  data_key = " . $dbh->quote($file_type))
    or &error_exit("admin4",$dbh->errstr);
    $dbh->commit();
  }
}

# Read lookup data needed for validation into hashes in memory
if ($validate eq "Y") { &populate_hashes() };

# Perform Stage, Validate and Move steps as requested
if ($stage eq "Y") { &stage() };
$all_valid = 0;
if ($file_type eq "cs") {
  if ($validate eq "Y") { $all_valid = &cs_validate() };
  if ($move eq "Y" && $all_valid) { &move(); &cs_load(); &append_user_input(PASS); 
  } else { &append_user_input(FAIL); }
} elsif ($file_type eq "dd") {
  if ($validate eq "Y") { $all_valid = &dd_validate() };
  if ($move eq "Y" && $all_valid) { &move(); &dd_load(); &append_user_input(PASS); 
  } else { &append_user_input(FAIL); }
} elsif ($file_type eq "lc") {
  if ($validate eq "Y") { $all_valid = &lc_validate() };
  if ($move eq "Y" && $all_valid) { &move(); &lc_load(); &append_user_input(PASS); 
  } else { &append_user_input(FAIL); }
} elsif ($file_type eq "rc") {
  if ($validate eq "Y") { &get_rl_fields(); $all_valid = &rc_validate() };
  if ($move eq "Y" && $all_valid) { &move(); &append_user_input(PASS); # No load, rc_merge instead  
  } else { &append_user_input(FAIL); }
} elsif ($file_type eq "rl") { 
  if ($validate eq "Y") { &get_rl_fields(); &get_rc_fields(); $all_valid = &rl_validate() };
  if ($move eq "Y") {
    if ($fullset eq "Y") {  # if full agency set then only load releases if ALL records are valid
      if ($all_valid) { &rl_load(); &move(); &append_user_input(PASSFULLSET);
      } else  { 
        printf("Rows found not valid, therefore unable to load and move as full RL dataset.\n\n"); 
        &append_user_input(FAIL) };
    } else { &rl_load();    # if NOT full agency set then load ALL records that are valid (Partial Set)
      if ($all_valid) { &move(); &append_user_input(PASS); 
      } else { &append_user_input(FAIL) };
    }
  }
}

# refresh data in desc_status and load_dates tables
&refresh_status();

# clear running flag so other jobs of this file_type can run
$last_valid = ($all_valid?"Y":"N");
$dbh->do("
  UPDATE admin_042
  SET    running = 'N', last_valid = " . $dbh->quote($last_valid) . "
  WHERE  data_key = " . $dbh->quote($file_type))
  or &error_exit("admin5",$dbh->errstr);
$dbh->commit();

printf(scalar(localtime) . ": Disconnecting from $db_name database\n\n");
$dbh->disconnect;

exit(1);

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  FUNCTIONS  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

#****************************************************************************
# Name: translate 
# Description: translate format 041 data file into format 042 data file 
#****************************************************************************

sub translate {
  printf(scalar(localtime) . ": Translating $file_name\n\n");

  $tranfilename  = "tran_" . $file_type . "_" . $agency . "_" . $year . ".csv";
  $from_file_name = $file_name;
  $to_file_name = $tranpath . "/" . $tranfilename;
  $reporting_agency = $agency;

## TESTING - line to see paramters being passed
  if ($TESTING eq "Y") {
    printf("Sending translate paramters: from_file - [%s], to_file_name - [%s], reporting_agency - [%s]\n", $from_file_name, $to_file_name, $reporting_agency);
  }

  $file_translated = "Y";
  $tran_message = "";
  if ($file_type eq "lc") {
    if (!(&lc_translate_to_042($from_file_name, $to_file_name, $reporting_agency))) {
       $file_translated = "N";
    }
  } elsif ($file_type eq "rl") {
    if (!(&rl_translate_to_042($from_file_name, $to_file_name, $reporting_agency))) {
       $file_translated = "N";
    }
  } elsif ($file_type eq "rc") {
    if (!(&rc_translate_to_042($from_file_name, $to_file_name, $reporting_agency))) {
       $file_translated = "N";
    }
  } elsif ($file_type eq "cs") {
    if (!(&cs_translate_to_042($from_file_name, $to_file_name, $reporting_agency))) {
       $file_translated = "N";
    }
  } elsif ($file_type eq "dd") {
    if (!(&dd_translate_to_042($from_file_name, $to_file_name, $reporting_agency))) {
       $file_translated = "N";
    }
  } else {
    $tran_message = "Translation Failed - Unknown File Type [" . $file_type . "]\n";
  }

  if ($file_translated eq "Y") {
    printf("Translation Stat - [%s]\n", $tran_message);
    printf("\n");
  } else {
    printf("Translation Failed - [%s]\n", $tran_message);
    exit(1);
  }    
}

#****************************************************************************
# Name: stage
# Description: Stage a file into the unvalidated directory.
#****************************************************************************

sub stage {
  printf(scalar(localtime) . ": STAGING $file_name to $uvalpath/$std_file_name\n");
  printf("\n");
  system("dos2unix -n " . $file_name . " " . $uvalpath . "/" . $std_file_name);
}

#****************************************************************************
# Name: move
# Description: Move a file from the unvalidated directory to the 
#              validated directory.
#****************************************************************************

sub move {
  printf(scalar(localtime) . ": MOVING $std_file_name from $uvalpath to $valpath\n");
  printf("\n");
  rename("$uvalpath/$std_file_name", "$valpath/$std_file_name");
}

#****************************************************************************
# Name: append_user_input 
# Description: Append date time stamp and pass/fail indicator to end of  
#              users input file.
#****************************************************************************

sub append_user_input {
  $val_status = $_[0];
  $append_file_name = $input_file_name . "-" . get_timeStampNow() . "-" . $val_status; 
  printf(scalar(localtime) . ": APPENDING time stamp: updated file name - $append_file_name \n");
  printf("\n");
  system("/bin/mv $input_file_name $append_file_name");
  #system("/bin/chown rmpcdb:mc_admin $append_file_name");
}

#****************************************************************************
# Name: error_exit                                                           
# Description: Called whenever an SQL error occurs. It prints the error      
#              number and the text of the error message, rolls back any      
#              uncommited database changes, clears the "running flag" in the 
#              admin table, disconnects from the database and terminates     
#              the load_psc program.                                         
#****************************************************************************

sub error_exit {
  my ($msg_number, $err_msg) = @_;
  printf("error_exit: %s\n", $msg_number);
  printf("error_exit: %s\n", $err_msg);
  $dbh->rollback();
  $dbh->do("
    UPDATE admin_042
    SET    running = 'N'
    WHERE  data_key = " . $dbh->quote($file_type));
  $dbh->commit();
  $dbh->disconnect;
  printf("error_exit: terminating program\n");
  print scalar(localtime), "\n";
  exit(1);
}

#****************************************************************************
# Name: load_log                                                             
# Description: Called to write information about the load job currently      
#              running to a logging table.                                   
# Inputs: load_type       Action to be logged: v (validate) or m (move).
#         number_of_rows  Number of rows processed.
#         validated_rows  Number of rows successfully validated.
#****************************************************************************

sub load_log {
  my ($load_type, $number_of_rows, $validated_rows, $load_year);
  ($load_type, $number_of_rows, $validated_rows) = @_;
  ($year eq "none") ? ($load_year = "0") : ($load_year = $year);
  $sth = $dbh->prepare("
      INSERT INTO load_log
      VALUES (?, ?, localtimestamp(0), ?, ?::int, ?, ?::bigint, ?::bigint, ?)
    ") or &error_exit("load_log1",$dbh->errstr);
  $sth->execute($load_type, $file_type, $agency, $load_year, $file_name,
                $number_of_rows, $validated_rows, $processing)
    or &error_exit("load_log2",$sth->errstr);
  $sth->finish;
  $dbh->commit();
}

#****************************************************************************
# Name: refresh_status                                                       
# Description: Called to refresh the desc_status and load_dates tables
#****************************************************************************

sub refresh_status {
  printf(scalar(localtime) . ": Refreshing Data Status tables\n");

  #MODIFY load_dates TO TRUNCATED
  $dbh->do("
      TRUNCATE TABLE load_dates
    ")
    or &error_exit("load_dates1",$dbh->errstr);

  printf(scalar(localtime) . ": load_dates TRUNCATE TABLE complete\n");

  $dbh->do("
      INSERT INTO load_dates
      SELECT file_type, year::text, agency, TO_CHAR(load_time,'YYYY/MM/DD'),
             MIN(load_type), load_time, processing 
      FROM   load_log ll
      WHERE  file_type IN ('cs','lc','rc','rl')
      AND    EXISTS (SELECT lm.load_time
                     FROM   load_max lm
                     WHERE  ll.file_type = lm.file_type
                     AND    ll.year::text = lm.year::text
                     AND    ll.agency = lm.agency
                     AND    ll.load_time = lm.load_time)
      GROUP BY file_type, year, agency, load_time, processing
    ")
    or &error_exit("load_dates2",$dbh->errstr);

  printf(scalar(localtime) . ": load_dates INSERT INTO complete\n");

  $dbh->do("
      UPDATE load_dates ld
      SET    moved = 'p'
      WHERE  EXISTS (SELECT ll.load_time
                     FROM   load_log ll
                     WHERE  ld.file_type = ll.file_type
                     AND    ld.year::text = ll.year::text
                     AND    ld.agency = ll.agency
                     AND    ll.load_time = (SELECT MAX(ll2.load_time)
                                            FROM   load_log ll2
                                            WHERE  ll2.file_type = ll.file_type
                                            AND    ll2.year::text = ll.year::text
                                            AND    ll2.agency = ll.agency
                                            AND    ll2.load_type = ll.load_type)
                     AND    ll.load_type = 'v'
                     AND    (ll.number_of_rows > ll.validated_rows OR
                             (ll.validated_rows IS NULL AND ld.moved = 'v')))
      ")
    or &error_exit("load_dates3",$dbh->errstr);

  $dbh->do("
      UPDATE load_dates
      SET    moved = 'm'
      WHERE  file_type = 'rc'
      AND    moved = 'v'
    ")
    or &error_exit("load_dates4",$dbh->errstr);

  $dbh->do("
      UPDATE load_dates
      SET    moved = 'v'
      WHERE  file_type = 'rc'
      AND    moved = 'm'
      AND    load_time > (SELECT MAX(load_time) 
                          FROM load_log
                          WHERE load_type = 'x')
    ")
    or &error_exit("load_dates5",$dbh->errstr);

  $dbh->do("
      TRUNCATE TABLE desc_status 
    ")
    or &error_exit("desc_status1",$dbh->errstr);

  $dbh->do("
      INSERT INTO desc_status
      SELECT file_type, COALESCE(file_year,'0')::text, reporting_agency,
             submission_status::text || '/' || file_status::text, NULL, NULL
      FROM   description_dates
      WHERE  file_type IN ('cs','lc','rc','rl')
    ")
    or &error_exit("desc_status2",$dbh->errstr);

  $dbh->do("
      INSERT INTO desc_status
      SELECT file_type, year::text, agency, '&nbsp', MIN(load_type),
             load_time
      FROM   load_log ll
      WHERE  file_type IN ('cs','lc','rc','rl')
      AND    EXISTS (SELECT lm.load_time
                     FROM   load_max lm
                     WHERE  ll.file_type = lm.file_type
                     AND    ll.year::text = lm.year::text
                     AND    ll.agency = lm.agency
                     AND    ll.load_time = lm.load_time)
      GROUP BY file_type, year, agency, load_time
    ")
    or &error_exit("desc_status3",$dbh->errstr);

  $dbh->do("
      UPDATE desc_status ds
      SET    moved = 'p'
      WHERE  EXISTS (SELECT ll.load_time
                     FROM   load_log ll
                     WHERE  ds.file_type = ll.file_type
                     AND    ds.year::text = ll.year::text
                     AND    ds.agency = ll.agency
                     AND    ll.load_time = (SELECT MAX(ll2.load_time)
                                            FROM   load_log ll2
                                            WHERE  ll2.file_type = ll.file_type
                                            AND    ll2.year::text = ll.year::text
                                            AND    ll2.agency = ll.agency
                                            AND    ll2.load_type = ll.load_type)
                     AND    ll.load_type = 'v'
                     AND    (ll.number_of_rows > ll.validated_rows OR
                             (ll.validated_rows IS NULL AND  ds.moved = 'v')))
      ")
    or &error_exit("desc_status4",$dbh->errstr);

  $dbh->do("
      UPDATE desc_status
      SET    moved = 'm'
      WHERE  file_type = 'rc'
      AND    moved = 'v'
    ")
    or &error_exit("desc_status5",$dbh->errstr);

  $dbh->do("
      UPDATE desc_status
      SET    moved = 'v'
      WHERE  file_type = 'rc'
      AND    moved = 'm'
      AND    load_time > (SELECT MAX(load_time) 
                          FROM load_log
                          WHERE load_type = 'x')
    ")
    or &error_exit("desc_status6",$dbh->errstr);

  $dbh->commit();
}

# Setup_Environment
# -----------------------------------------------------------------------------
sub Setup_Environment  {

  #$db_name        = $ENV{PG_DATABASE}; NOTE: $db_name passed as a parameter
  $user            = $ENV{RMPCDB_USER};
  $passwd          = $ENV{RMPCDB_PASS};
  $binpath         = $ENV{RMPCDB_BIN};
  $uvalpath        = $ENV{CWT_UVAL};
  $valpath         = $ENV{CWT_VAL};
  $logpath         = $ENV{CWT_LOG};
  $tranpath        = $ENV{CWT_ACCT} . "/tran";
  $current_format  = "4.2";
  $flag            = "Y";

  $TESTING 	   = "N";
 
}
