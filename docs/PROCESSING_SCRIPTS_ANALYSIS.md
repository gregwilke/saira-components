# Saira Processing Scripts Analysis

## Overview
Analysis of the core PSC (Pacific Salmon Commission) data processing scripts extracted from Saira server. These scripts form the critical bridge between Horus validation and Saira database storage.

## Core Processing Architecture

### 1. **Main Data Loading Script: `load_psc.pl`**

**Purpose**: Primary data processing orchestrator for PSC format data  
**Size**: 25KB (highly complex, mission-critical)  
**Location**: `/home/rmpcdb/bin/load_psc.pl`

#### **Command Line Interface**
```bash
load_psc.pl db_name file_type agency year trans stage val move midyr fullset format file_name

# Example:
load_psc.pl rpro cs ADFG 2000 N Y Y Y N N 4.2 /home/rmis/up/cs_ADFG_2000.csv
```

#### **Parameters Explained**
- **`db_name`**: Target database (rpro=production, rrep=reporting, rdev1-3=development)  
- **`file_type`**: PSC data type (`cs`=Catch Sample, `rc`=Recovery, `rl`=Release, `lc`=Location, `dd`=Description)
- **`agency`**: Reporting agency code (ADFG, WDFW, ODFW, CDFO, etc.)
- **`year`**: Data year
- **`trans`**: Translation flag (Y/N) - Convert legacy formats to PSC v4.2
- **`stage`**: Staging flag (Y/N) - Copy to unvalidated directory  
- **`val`**: Validation flag (Y/N) - Run format validation
- **`move`**: Move flag (Y/N) - Move to validated directory after validation
- **`midyr`**: Mid-year processing flag (Y/N)
- **`fullset`**: Full dataset flag (Y/N) - Process complete agency dataset
- **`format`**: PSC format version (4.2 current, 4.1 legacy)
- **`file_name`**: Input file path

#### **Processing Workflow**
1. **Translation Phase**: Convert legacy PSC formats to current v4.2
2. **Staging Phase**: Copy files to unvalidated directory (`/usr/cwt/csv/rpro/unvalidated/`)
3. **Validation Phase**: Call appropriate validation module based on file type
4. **Move Phase**: Transfer validated files to validated directory (`/usr/cwt/csv/rpro/validated/`)
5. **Database Load**: Import validated data into PostgreSQL tables

#### **File Type Processing**
```perl
if ($file_type eq "cs") {
  if ($validate eq "Y") { $all_valid = &cs_validate() };
} elsif ($file_type eq "dd") {
  if ($validate eq "Y") { $all_valid = &dd_validate() };
} elsif ($file_type eq "lc") {
  if ($validate eq "Y") { $all_valid = &lc_validate() };
} elsif ($file_type eq "rc") {
  if ($validate eq "Y") { &get_rl_fields(); $all_valid = &rc_validate() };
} elsif ($file_type eq "rl") {
  if ($validate eq "Y") { &get_rl_fields(); &get_rc_fields(); $all_valid = &rl_validate() };
}
```

### 2. **Validation Orchestrator: `runval.pl`**

**Purpose**: Wrapper script for validation processing with logging and email notifications  
**Size**: 11KB  
**Location**: `/home/rmpcdb/bin/runval.pl`

#### **Key Features**
- **Automated Logging**: Creates timestamped validation logs
- **Email Notifications**: Sends results to submitting agencies
- **URL Generation**: Provides web links to validation reports
- **Error Handling**: Comprehensive error capture and reporting

#### **Integration Points**
- **Input Directory**: `/net/horus/usr/home/{AGENCY}/up/` (NFS mounted from Horus)
- **Log Directory**: `/net/horus/usr/pub_horus/logs/` (Shared with Horus)
- **Report Directory**: `/net/horus/usr/pub_horus/user_reports/` (Public access)

### 3. **Validation Modules (Perl Modules)**

#### **Recovery Validation: `rc_validate.pm`**
**Purpose**: Validates Pacific salmon recovery (catch) data  
**Size**: 53KB (most complex validation module)

**Core Validation Checks**:
1. **CSV Format Validation**: Ensures proper comma-separated format
2. **ASCII Character Check**: Prevents encoding issues
3. **Field Length Validation**: Enforces PSC format field limits
4. **Date Validation**: Comprehensive date format and range checks
5. **Species Validation**: Cross-references against species lookup tables
6. **Tag Code Validation**: Links to release records for tag consistency
7. **Location Validation**: Verifies recovery location codes
8. **Weight/Length Limits**: Species-specific biological limits
   - Chinook: Weight limits, length < 1600mm
   - Other species: Length < 1300mm
9. **Blank Wire Validation**: Special handling for untagged fish
10. **Cross-reference Checks**: Recovery data consistency with release records

#### **Release Validation: `rl_validate.pm`**
**Purpose**: Validates Pacific salmon release (tagging) data  
**Size**: 60KB (largest validation module)

**Core Validation Checks**:
1. **Tag Code Uniqueness**: Ensures no duplicate tag codes
2. **Related Group Analysis**: Validates release group relationships
3. **Hatchery Validation**: Cross-references hatchery location codes
4. **Stock Validation**: Verifies stock origin information
5. **Mark Validation**: Coded wire tag and visual mark consistency
6. **Count Validation**: Tagged vs. untagged fish counts
7. **Release Date Validation**: Temporal consistency checks
8. **Study Type Validation**: Research protocol compliance

#### **Other Validation Modules**:
- **`cs_validate.pm`**: Catch Sample validation
- **`lc_validate.pm`**: Location data validation  
- **`dd_validate.pm`**: Description data validation

## Environment and Integration

### **Critical Environment Variables**
```bash
CWT_LOG=/net/horus/usr/pub_horus/logs          # Horus log integration
CWT_POST_DATA=/net/horus/usr/pub_horus/data    # Data posting location
CWT_ACCT=/net/horus/usr/home                   # Agency directory access
CWT_UVAL=/usr/cwt/csv/rpro/unvalidated         # Staging area
CWT_VAL=/usr/cwt/csv/rpro/validated            # Validated storage
RMPCDB_USER=rmis_holder                        # Database user
RMPCDB_PASS=BlueSail*Haacke.1964              # Database password
```

### **Directory Structure**
```
/usr/cwt/csv/rpro/
├── unvalidated/          # Staged files awaiting validation
├── validated/            # Successfully validated files
└── processed/            # Files loaded into database

/net/horus/usr/home/      # NFS mount to Horus agency directories
├── ADFG/up/             # Alaska Dept Fish & Game uploads
├── WDFW/up/             # Washington Dept Fish & Wildlife uploads
├── ODFW/up/             # Oregon Dept Fish & Wildlife uploads
└── {AGENCY}/up/         # Other agency upload directories
```

## Database Integration

### **PostgreSQL Connection**
- **Primary Database**: `rpro` (production)
- **User**: `rmis_holder` (full read/write access)
- **Host**: `localhost` (Saira server)

### **Key Database Operations**
1. **Load Logging**: Tracks all processing attempts in `load_log` table
2. **Status Updates**: Maintains `desc_status` for web interface
3. **Data Import**: Bulk loads into `*_042` tables (recoveries_042, releases_042, etc.)
4. **Validation State**: Tracks validation status and error counts

## Error Handling and Monitoring

### **Validation Error Types**
1. **Format Errors**: CSV structure, field lengths, data types
2. **Business Logic Errors**: Species limits, date ranges, location validity
3. **Cross-reference Errors**: Tag codes not found in releases
4. **Data Integrity Errors**: Duplicate records, missing required fields

### **Logging and Notifications**
- **Validation Logs**: Detailed error reports with line numbers
- **Email Alerts**: Automatic notifications to `rmpcdb.admin@psmfc.org`
- **Web Reports**: Public access via `https://www.rmpc.org/pub/di_reports/`
- **Status Pages**: Real-time validation status on RMIS website

## Automation Integration

### **Cron Integration**
```bash
# Daily auto-merge processing (7:00 PM)
0 19 * * * $RMPCDB_BIN/auto_merge_submission.sh

# Nightly data submission (8:00 PM)  
0 20 * * * $RMPCDB_BIN/post_nightly_psc_submit.pl

# Semi-weekly RAR summary rebuild
04 4 * * 4,7 psql -c 'SELECT rarsr_summarize_all();'
```

### **Queue Processing**
- **`qrun`**: Runs every minute to process validation queue
- **File Monitoring**: Integration with Horus `ckrmisfilechange` script
- **Auto Processing**: Hands-off processing for validated submissions

## Data Flow Integration

### **Complete Pipeline**
```
1. HORUS UPLOAD:
   rmis-files (JS) → rmis-api (NodeJS) → /usr/home/{AGENCY}/up/

2. HORUS VALIDATION:
   ckrmisfilechange → PSC validation → Manual approval → NFS transfer

3. SAIRA PROCESSING:
   qrun → runval.pl → load_psc.pl → PostgreSQL

4. DATABASE INTEGRATION:
   Validated data → *_042 tables → Query views → RMIS website
```

### **Critical Integration Points**
- **NFS File Sharing**: Seamless file transfer between Horus and Saira
- **Shared Logging**: Common log directory accessible from both servers
- **Email Coordination**: Unified notification system
- **Status Synchronization**: Real-time status updates across systems

## Technical Debt and Modernization Notes

### **Legacy Components**
1. **Perl Codebase**: 20+ year old Perl scripts with extensive business logic
2. **Text::CSV Processing**: Line-by-line file parsing (performance limitations)
3. **System Commands**: Heavy use of shell commands and external utilities
4. **Hard-coded Paths**: Environment-specific path dependencies

### **Security Considerations**
1. **Database Credentials**: Plain-text passwords in environment variables
2. **File Permissions**: Complex permission structure for multi-user access
3. **Input Validation**: Comprehensive but legacy validation logic

### **Performance Characteristics**
1. **Single-threaded Processing**: Sequential file processing
2. **Memory Efficient**: Streaming CSV processing
3. **Database Optimized**: Bulk insert operations
4. **Network Dependent**: NFS-based file operations

## Modernization Opportunities

### **High Priority**
1. **API Integration**: Replace file-based processing with REST API calls
2. **Credential Management**: Secure credential storage and rotation
3. **Containerization**: Docker-based deployment for consistency
4. **Monitoring Enhancement**: Real-time performance and error tracking

### **Medium Priority**
1. **Language Migration**: Consider Python/NodeJS for new components
2. **Database Connection Pooling**: Improve database efficiency
3. **Parallel Processing**: Multi-threaded validation for large files
4. **Cloud Storage**: Replace NFS with cloud-based file storage

### **Critical Preservation**
1. **Business Logic**: 50+ years of fisheries management rules
2. **Data Integrity**: Scientific validation requirements
3. **Agency Workflows**: Established submission processes
4. **Historical Compatibility**: Ability to process legacy data formats

---

**This analysis reveals the processing scripts as the critical heart of the RMPC system - a sophisticated, battle-tested data processing pipeline that handles millions of Pacific salmon records with scientific precision and regulatory compliance.**