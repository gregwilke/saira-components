# Saira Server Cron Job Analysis

## Overview
Complete analysis of cron jobs and automated tasks on the Saira server (`saira.psmfc.org`), extracted from production system configuration.

## Main Cron Configuration

### System Crontab (`/etc/crontab`)
The main crontab includes RMPC-specific cron directories added by DLW on 2024-01-02:

```cron
# RMPC-specific cron jobs
01 *    * * *   rmpcdb  run-parts /etc/cron.rmpcdb.hourly
02 4    * * *   rmpcdb  run-parts /etc/cron.rmpcdb.daily  
22 4    * * 0   rmpcdb  run-parts /etc/cron.rmpcdb.weekly
42 4    1 * *   rmpcdb  run-parts /etc/cron.rmpcdb.monthly
```

### Schedule Summary
- **Hourly**: Every hour at 1 minute past (01:01, 02:01, etc.)
- **Daily**: Every day at 4:02 AM
- **Weekly**: Sundays at 4:22 AM
- **Monthly**: 1st day of each month at 4:42 AM

## Queue Management System

### `qrun` - Queue Processor
**Location**: `/usr/local/sbin/qrun`  
**Schedule**: Every minute (via system cron or external trigger)  
**Purpose**: Ensures single-threaded job execution for validation pipeline

**Key Features**:
- Uses file locking (`/var/tmp/qrun.lk`) to prevent concurrent runs
- Checks for running processes via `atq` command
- Runs `atrun -l 3.0` to process next queued job
- Critical for maintaining data integrity during processing

## Hourly Jobs (`/etc/cron.rmpcdb.hourly/`)
**Schedule**: Every hour at 1 minute past  
**Status**: Currently empty - no hourly RMPC jobs configured

## Daily Jobs (`/etc/cron.rmpcdb.daily/`)
**Schedule**: Every day at 4:02 AM  
**Status**: Currently empty - no daily RMPC jobs configured

## Weekly Jobs (`/etc/cron.rmpcdb.weekly/`)
**Schedule**: Sundays at 4:22 AM

### Data Publishing Jobs (4 total)
1. **`post_weekly_psc_data_dd`** - Descriptions Table Export
   - Creates CSV copy of Descriptions table
   - Output: `/usr/pub_horus/data/DD042_ALL_none.csv`
   - Web access: `https://www.rmpc.org/pub/data/`

2. **`post_weekly_psc_data_lc`** - Locations Table Export
   - Creates CSV copy of Locations table
   - Output: `/usr/pub_horus/data/LC042_ALL_none.csv`

3. **`post_weekly_psc_data_rl`** - Releases Table Export
   - Creates CSV copy of Releases table
   - Output: `/usr/pub_horus/data/RL042_ALL_none.csv`

4. **`post_weekly_psc_for_exchange`** - Data Exchange Files
   - Creates data exchange files for partner organizations
   - Supports inter-agency data sharing requirements

## Monthly Jobs (`/etc/cron.rmpcdb.monthly/`)
**Schedule**: 1st day of each month at 4:42 AM

### Data Integrity Reports (15 total)

#### General Data Quality Reports
1. **`missing_region_basin_rpt`** - Missing Region/Basin Data
   - Identifies records with missing geographic classification
   - Critical for spatial analysis and reporting

2. **`duplicate_location_name_rpt`** - Duplicate Location Names
   - Detects location code conflicts and naming inconsistencies
   - Essential for data dictionary maintenance

3. **`mis_coded_blank_wire_rpt`** - Miscoded Blank Wire Tags
   - Identifies incorrectly coded blank wire (untagged) fish
   - Important for statistical analysis accuracy

4. **`si_rgi_rpt`** - Study Information Report
   - Validates study information and research group data
   - Ensures research protocol compliance

#### Biological Validation Reports
5. **`rc_chinook_wt_gt_allowed`** - Chinook Weight Validation
   - Identifies Chinook salmon with weights exceeding biological limits
   - Critical for data quality and scientific integrity

6. **`rc_salmon_wt_gt_allowed`** - Salmon Weight Validation
   - Validates weight measurements across all salmon species
   - Catches data entry errors and outliers

7. **`rc_length_gt_1300_rpt`** - Fish Length > 1300mm
   - Reports fish with length measurements exceeding 1300mm
   - Species-specific validation (non-Chinook species)

8. **`rc_length_gt_1600_rpt`** - Fish Length > 1600mm
   - Reports fish with length measurements exceeding 1600mm
   - Chinook-specific validation threshold

#### Hatchery-Specific Reports (8 total)

##### Recovery Reports (4 total)
- **`rc_coastal_hatcheries`** - Coastal Hatchery Recovery Data
- **`rc_central_valley_hatcheries`** - Central Valley Hatchery Recovery Data
- **`rc_klamath_hatcheries`** - Klamath Basin Hatchery Recovery Data
- **`rc_warm_springs_hatcheries`** - Warm Springs Hatchery Recovery Data

##### Release Reports (4 total)
- **`rl_coastal_hatcheries`** - Coastal Hatchery Release Data
- **`rl_central_valley_hatcheries`** - Central Valley Hatchery Release Data
- **`rl_klamath_hatcheries`** - Klamath Basin Hatchery Release Data
- **`rl_warm_springs_hatcheries`** - Warm Springs Hatchery Release Data

## Yearly Jobs (`/etc/cron.rmpcdb.yearly/`)
**Schedule**: Annually (specific date/time not configured)  
**Status**: Currently empty - no yearly RMPC jobs configured

## Integration and Infrastructure

### Environment Setup
All cron scripts source environment variables from:
```bash
. /usr/local/bin/set_env_vars.sh
```

### Email Notifications
- **Recipient**: `rmpcdb.admin@psmfc.org`
- **Content**: Error reports, completion notifications, and data integrity alerts
- **Frequency**: As needed based on job execution and error conditions

### Web Publishing
- **Data Reports**: `https://www.rmpc.org/pub/di_reports/`
- **Data Files**: `https://www.rmpc.org/pub/data/`
- **Public Access**: Available to authorized users and partner agencies

### File Locations
- **Scripts**: `/etc/cron.rmpcdb.{hourly,daily,weekly,monthly}/`
- **Logs**: `/tmp/` (temporary files with process IDs)
- **Output**: `/usr/pub_horus/data/` (shared with Horus server)

## System Integration

### Data Flow
1. **Processing Pipeline**: Validated data from Horus → Saira database
2. **Quality Control**: Monthly integrity reports identify issues
3. **Data Publishing**: Weekly exports provide current data snapshots
4. **Stakeholder Access**: Web-based access to reports and data files

### Critical Dependencies
- **Database**: PostgreSQL `rpro` database connectivity
- **File System**: NFS mounts to Horus server (`/usr/pub_horus/`)
- **Email System**: Sendmail for notifications
- **Web Server**: Apache for public data access

## Operational Characteristics

### Reliability Features
- **Single Threading**: `qrun` prevents concurrent job execution
- **Error Handling**: Comprehensive error capture and email notifications
- **Logging**: Temporary files for debugging and monitoring
- **Lock Files**: Prevents race conditions in queue processing

### Performance Considerations
- **Scheduled Timing**: Jobs scheduled during low-usage periods (early morning)
- **Resource Management**: Sequential execution prevents system overload
- **Data Staging**: Temporary files minimize database lock times

## Maintenance and Monitoring

### Regular Tasks
- **Monthly**: Review data integrity reports for anomalies
- **Weekly**: Verify data publishing completed successfully
- **Daily**: Monitor queue processing and error notifications
- **Continuous**: `qrun` queue processor ensures timely data processing

### Alert Conditions
- **Failed Jobs**: Email notifications for script failures
- **Data Anomalies**: Integrity reports highlight data quality issues
- **System Issues**: Queue processor failures or database connectivity problems

## Historical Context

### Development Timeline
- **2016-2018**: Initial cron system development (JRL)
- **2023**: PSC Format 4.2 migration updates (DLW)
- **2024**: System modernization and Ubuntu 24.04 compatibility (JRL, DLW)

### Key Contributors
- **JRL (Jim Longwill)**: Primary system architect and maintainer
- **DLW (Dan Webb)**: System administration and format updates

---

**This cron system provides comprehensive automated data processing, quality control, and publishing for the Pacific salmon management system, ensuring data integrity and availability for fisheries management decisions across the Pacific Northwest.**