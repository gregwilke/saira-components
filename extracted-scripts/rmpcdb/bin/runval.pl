#!/usr/local/bin/perl -w
#
# ****************************************************************************
# Name:          runval.pl
# Description: 	 Wrapper program to run load_psc.pl and generate log files. 
#
#****************************************************************************
# Program History for Format Ver 4.2
# INT  DATA      Comments
# ---  --------  --------
# DLW  20230711  Begin modifications for Format Ver 4.2
#                remove references to "ce" data type
# DLW  20240516  Moved /usr/pub on Gilli to /usr/pub_horus on Horus
#
# -----------------------------------------------------------------------------
# Program History prior to Format Ver 4.2
# INT  DATE      Comments
# ---  --------  --------
# DLW  20030716  Coppied from Onco System
# DLW  20050502  Added bkdev as a valid database option
# DLW  20060112  Updated db_name to full database name cpro.psmfc.org to 
#                work with new install of Oracle 10g 
# DLW  20070907  Added unix2dos system call to convert log files to dos format
#                for browser compatibility issues with Internet Explorer.
# JRL  20071022  Added new flag (fullset) for processing releases as fullset of data.
# JRL  20071114  Added section in subroutine 'createlogs' to create
#		 current-time-stamped log file if fullset is 'Y'
# DLW  20080818  Expande agency field length from 4 to 10 characthers
# DLW  20090324  Modifications for Ver 4.1 Validation (change all instances
#                of "4.0" to "4.1"
# DLW  20140717  Update program to auto email log results to user.  See sub &maillog
#                Update parameter list to accept $user_email as users email address
# DLW  20161028  Update program to display .elog and .slog URLs 
# DLW  20210503  Replaced "ftp" .log .elog and .slog URLs with "www". 
# -----------------------------------------------------------------------------
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  DECLARATIONS  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

use lib $ENV{RMPCDB_BIN};

my($now_rawyear
  ,$now_rawdeltamonth
  ,$now_rawday
  ,$now_rawhour
  ,$now_rawminute
  ,$now_formattedyear
  ,$now_rawmonth
  ,$now_formattedmonth
  ,$now_formattedday
  ,$now_formattedhour
  ,$now_formattedminute
  ,$now_timestamp
  ) = 0;  

my($archive_log_file_full_name) = '';

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  DRIVER  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

&Setup_Environment();

# Validating number of parameters
if ($#ARGV != 12) {
  printf("usage: ./runval.pl db_name           file_type agency year trans stage val move midyear fullset format file_name user_email\n");
  printf("ex:    ./runval.pl cpro.psmfc.org    cs        ADFW   1999   N     Y    Y   Y      N       N     4.2   /usr/home/ADFG/up/cs_ADFG_2000.csv user.acct\@psmfc\.org\n");
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
$user_email  = $ARGV[12];

$file_type   = lc($file_type);
$agency      = uc($agency);
$stage       = uc($stage); 
$validate    = uc($validate); 
$move        = uc($move); 
$midyear     = uc($midyear); 
$fullset     = uc($fullset);

$valid = "Y";

# Validating the db_name parameters
if (($db_name ne "rpro") && ($db_name ne "rrep") && ($db_name ne "rdev1") && ($db_name ne "rdev2") && ($db_name ne "rdev3")) {
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
  printf("Parameter error: agency format not recognized yet [%s]\n", $agency);
  $valid = "N";
}

# Validating the translate, stage, validate, move, fullset, midyear parameters
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

#Determine Log File and Extention
$log_file_name = "load_psc_" . $file_type . "_" . $agency . "_" . $year;
$log_file_ext  = "log";
if ($midyear eq "Y") {
  $log_file_ext     = "log-midyr";
}
$log_file_full_name = $logpath . "/" . $log_file_name . "." . $log_file_ext;
#printf("Log File [%s]\n", $log_file_full_name);

#Execute Command
  $input_file_name = $file_name;
  &validate();
  &createlogs();
  system("unix2dos", "-k", $log_file_full_name);
  system("unix2dos", "-k", $logpath . "/" . $log_file_name . ".e" . $log_file_ext);
  system("unix2dos", "-k", $logpath . "/" . $log_file_name . ".s" . $log_file_ext);
  &maillog();
  exit(1);

sub validate {
  $valcommand    = $binpath . "/" . "load_psc.pl " . $db_name . " " . $file_type . " " .  $agency . " " . $year . " " . $translate . " " . $stage . " " . $validate . " " . $move . " " . $midyear . " " . $fullset . " " . $fmt_version . " " . $input_file_name . " > " . $log_file_full_name;
  system($valcommand);
}

sub createlogs {
  #OPEN Log file
  if (! open (INPUTLOG, "< " . $log_file_full_name)) {
    die "open INPUTLOG for input failed $log_file_full_name $!\n";
  }

  if (! open (ERRLOG, "> " . $logpath . "/" . $log_file_name . ".e" . $log_file_ext)) {
    die "open ERRLOG for output failed $!\n";
  }

  if (! open (SUMLOG, "> " . $logpath . "/" . $log_file_name . ".s" . $log_file_ext)) {
    die "open SUMLOG for output failed $!\n";
  }

  if (! dbmopen %erl, "/tmp/erl$$", 0666) {
    die "dbmopen erllog file for array failed $!\n";
  }

  if (! dbmopen %srl, "/tmp/srl$$", 0666) {
    die "dbmopen srllog file for array failed $!\n";
  }

  while ($linein = <INPUTLOG>){
    if (($msg) = $linein =~ /(\|.*)/) { 
      $erl{$msg}++;
    } else {
      print ERRLOG $linein;
    }
    if (($msg) = $linein =~ /(\|.*)\;/) { 
      $srl{$msg}++;
    } else { 
      print SUMLOG $linein;
    }
  }

  foreach $msg (sort keys %erl) {
    printf ERRLOG "%8s = %s \n", $erl{$msg}, $msg;
  }

  foreach $msg (sort keys %srl) {
    printf SUMLOG "%8s = %s \n", $srl{$msg}, $msg;
  }
  dbmclose %erl;
  dbmclose %srl;
  unlink </tmp/srl$$.*>;
  unlink </tmp/erl$$.*>;

  if ($fullset eq "Y") {
    # Get timestamp now
    ($now_rawminute
      ,$now_rawhour
      ,$now_rawday
      ,$now_rawdeltamonth
      ,$now_rawyear) = (localtime(time))[1..6];

    $now_formattedyear	= $now_rawyear + 1900;
    $now_rawmonth	= $now_rawdeltamonth + 1;

    if (length($now_rawmonth) == 1) {
      $now_formattedmonth = '0' . $now_rawmonth;
    } else {
      $now_formattedmonth = $now_rawmonth;
    }

    if (length($now_rawday) == 1) {
      $now_formattedday   = '0' . $now_rawday;
    } else {
      $now_formattedday   = $now_rawday;
    }

    if (length($now_rawhour) == 1) {
      $now_formattedhour = '0' . $now_rawhour;
    } else {
      $now_formattedhour = $now_rawhour;
    }

    if (length($now_rawminute) == 1) {
      $now_formattedminute   = '0' . $now_rawminute;
    } else {
      $now_formattedminute   = $now_rawminute;
    }
    $now_timestamp = $now_formattedyear
	. $now_formattedmonth
	. $now_formattedday
	. $now_formattedhour
	. $now_formattedminute;

    # Assign timestamp to filename
    $archive_log_file_full_name = $logpath . "/" . $log_file_name . '_' . $now_timestamp . "." . $log_file_ext;

    # Create timestamped logfile
    system("cp -fp $log_file_full_name $archive_log_file_full_name");
  }

}
sub maillog {

  my $rmpcadmin     = "rmpcdb.admin\@psmfc.org";
#  my $maillist      = $user_email;
  my $maillist      = $user_email . "," . $rmpcadmin;
  my $mailto        = $maillist;
  my $mailfrom      = "rmpcdb.admin\@psmfc.org";
  my $result_log    = `grep Result $log_file_full_name`;
  my $result_llog   = `grep "DATA LOAD FAILED" $log_file_full_name`;
  my $subject       = "";

  if ($file_type eq "cs" || $file_type eq "rc") {
     $file_disp = $agency . " " . $file_type . " " . $year;
  } else {
     $file_disp = $agency . " " . $file_type;
  }

  if ($result_llog eq "") {
     $subject = "$file_disp validation completed, $result_log";
  } else {
     $subject = "$file_disp validation completed but DATA LOAD FAILED";
  }

  my $log_file_URL  = $logurl . "/" . $log_file_name . "."  . $log_file_ext;
  my $elog_file_URL = $logurl . "/" . $log_file_name . ".e" . $log_file_ext;
  my $slog_file_URL = $logurl . "/" . $log_file_name . ".s" . $log_file_ext;

  if (! open(MAIL, "| /usr/local/bin/mailtofrom -t $mailto -f $mailfrom -s \"$subject\"")) {
    die "Could not open the mailtofrom program;$!\n";
 }

  select(MAIL);
  print "Reporting Agency: $agency\n";
  print "File Type:   $file_type\n";
  print "File Year:   $year\n";
  print "File Name:   $file_name\n\n";
  if ($result_llog eq "") {
      print "$result_log\n";
  } else {
      print "$result_llog\n";
      print "$result_log\n";
  }
  print "The results of your recent data submission can be viewed below and at: \n";
  print "$log_file_URL\n\n";
  print "$elog_file_URL\n\n";
  print "$slog_file_URL\n\n";
  print `cat $log_file_full_name 2> /dev/null`;

  close(MAIL);
}

# Setup_Environment
# -----------------------------------------------------------------------------
sub Setup_Environment  {

  $binpath         = $ENV{RMPCDB_BIN};
  $logpath         = $ENV{CWT_LOG};
  $logurl          = "https://www.rmpc.org/pub/logs";
  $current_format  = "4.2";
}
