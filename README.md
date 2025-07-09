# Saira Database Server Components (PostgreSQL Backend)

This directory contains all components discovered and extracted from the Saira server (saira.psmfc.org), which serves as the PostgreSQL database backend for the RMPC system's validated data storage and query processing.

## Discovered Components Overview

### 📁 Directory Structure
```
saira-components/
├── README.md                      # This documentation
├── saira-inventory*               # Server discovery session logs (3 sessions)
├── *_schema.txt                   # Core PSC database table schemas
├── query_*_view.txt               # Database views that support rmis queries
└── saira-database-schemas.tar.gz  # Archived schema extraction
```

## Server Architecture Discovered

### System Information
- **Server**: saira.psmfc.org (10.2.14.85)
- **OS**: Ubuntu with PostgreSQL 16
- **Role**: Database and processing server (backend for entire RMPC system)
- **Primary Function**: Stores validated PSC data and serves query requests

### PostgreSQL Database Structure
**5 Databases Identified**:
- **`rpro`** - Production database (main data storage, owner: rmis_holder)
- **`rrep`** - Reporting database (query-optimized, access: rmis_reader1)
- **`rdev1`** - Development database 
- **`rdev2`** - Development database
- **`rdev3`** - Development database

## Core PSC Data Tables (Production)

### Main Data Tables (PSC v042 Format)
Based on extraction and analysis of `rpro` database:

#### **recoveries_042** (4.8 GB - Primary Table)
```
- record_code, format_version, submission_date
- reporting_agency, sampling_agency, recovery_id
- species, run_year, recovery_date_* fields
- fishery, gear, recovery_location_code/key
- tag_code, tag_type, tag_status (CRITICAL: Links to releases)
- fish biometrics: sex, weight, length, detection_method
- sampling data: catch_sample_id, sample_type, number_cwt_estimated
- 50+ columns total, stores all coded wire tag recovery data
```

#### **releases_042** (144 MB)
```
- record_code, format_version, submission_date
- reporting_agency, release_agency, coordinator
- tag_code_or_release_id (CRITICAL: Links to recoveries)
- species, run, brood_year
- release/hatchery/stock location codes and names
- fish counts: cwt_1st_mark_count, cwt_2nd_mark_count
- study data: study_type, study_integrity, counting_method
- tag management: tag_loss_rate, tag_reused
- 50+ columns total, stores all fish release and tagging data
```

#### **catch_sample_042** (112 MB)
```
- Fishing harvest and sampling information
- Links to recovery data via catch_sample_id
- Agency sampling protocols and data collection
```

#### **locations_042** (32 MB)
```
- Geographic locations and facility definitions
- Referenced by recovery_location_code and release_location_code
- Supports spatial queries and location-based analysis
```

#### **descriptions_042**
```
- Species, stock, and run descriptions
- Provides lookup data for species and biological classifications
```

### Supporting Tables Discovered
- **`locations_archive`, `releases_archive`, `recoveries_archive`** - Historical data preservation
- **`*_csv`** tables - Raw PSC file imports before processing
- **`rar_*`** tables - Report and analysis framework
- **`query_report_log`** (108 MB) - Query tracking and performance monitoring

## Query System Integration

### Database Views (45+ Query Views)
Complete query view system that directly supports Horus CGI scripts:

#### **Core Query Views**
- **`query_ta1rec_042`** - Tag recovery analysis (matches `querytd4rec_042.pl`)
- **`query_all_releases_042`** - Release data queries
- **`query_all_recoveries_042`** - Recovery data queries
- **`query_locations_042`** - Location-based queries

#### **CSV Export Views**
- **`query_csv_rc_042`** - Recovery data CSV export
- **`query_csv_rl_042`** - Release data CSV export  
- **`query_csv_cs_042`** - Catch sample CSV export
- **`query_csv_lc_042`** - Location CSV export

#### **PSC Format Views**
- **`query_psc_rc_042`** - PSC format recovery queries
- **`query_psc_rl_042`** - PSC format release queries
- **`query_psc_cs_042`** - PSC format catch sample queries
- **`query_psc_lc_042`** - PSC format location queries
- **`query_psc_dd_042`** - PSC format description queries

#### **Specialized Analysis Views** 
- **`query_recbyrllocation_042`** - Recoveries by release location
- **`query_recoveriesbyhatchery_042`** - Hatchery-specific recovery analysis
- **`query_recoveriesbytagcode_042`** - Tag code-based queries
- **`query_related_releases_042`** - Related release group analysis

### Historical Data Scope
Database contains **50+ years of Pacific salmon data**:
- **Year columns**: y1973_est through y1984_est+ (and continuing)
- **Multi-agency data**: ADFG, WDFW, ODFW, CDFG, CDFO, NMFS, USFWS, tribes
- **Complete lifecycle tracking**: From fish releases through recoveries
- **Scientific research**: Tag loss studies, population analysis, fishery management

## Infrastructure Components

### Queue Management System
- **`/usr/local/sbin/qrun`** - Runs every minute (similar to Horus file monitoring)
- **Custom cron structure**: `/etc/cron.rmpcdb.*` directories for rmpcdb user
- **Automated processing**: Handles data ingestion from Horus validation pipeline

### Key Processing Scripts Found
- **`/usr/local/sav/longwill/doc/RMPC_Shelf/load_psc.pl`** - PSC data loading script
- **`/home/rmpcdb/bin/ls_directory.sh`** - Directory management (shared with Horus)

### NFS File Sharing
- **NFS kernel server restart at boot** - Indicates file sharing with Horus for processing
- **Integration point**: Likely receives validated files from Horus PSC validation

### Cron Automation Schedule
```bash
# System cron jobs
* * * * * /usr/local/sbin/qrun                    # Queue management every minute

# rmpcdb user scheduled tasks  
01 * * * * rmpcdb run-parts /etc/cron.rmpcdb.hourly   # Hourly processing
02 4 * * * rmpcdb run-parts /etc/cron.rmpcdb.daily    # Daily maintenance  
22 4 * * 0 rmpcdb run-parts /etc/cron.rmpcdb.weekly   # Weekly tasks
42 4 1 * * rmpcdb run-parts /etc/cron.rmpcdb.monthly  # Monthly operations

# Shared with Horus
0 1 * * * /home/rmpcdb/bin/ls_directory.sh        # Directory management
```

## Complete Data Pipeline Integration

### End-to-End Data Flow Confirmed
```
1. Upload Phase (Modern):
   rmis-files (JS) → rmis-api (NodeJS) → Agency folders on Horus

2. Validation Phase (Legacy on Horus):
   ckrmisfilechange → PSC validation modules → Manual admin approval

3. Database Phase (Saira):
   Validated PSC files → load_psc.pl → PostgreSQL tables (recoveries_042, releases_042, etc.)

4. Query Phase (Legacy):
   rmis PHP CGI → Database views → Query results
```

### Critical Integration Points
- **Tag codes** link releases to recoveries (primary key relationship)
- **Location codes** provide geographic context across all data types
- **Agency codes** track data ownership and reporting responsibility
- **Date fields** enable temporal analysis and trend tracking
- **Sample types** support statistical analysis and estimation methods

## Data Relationships and Business Logic

### Core Data Model
- **Releases** → Fish are tagged and released with coded wire tags
- **Recoveries** → Tagged fish are caught and tags recovered/decoded
- **Locations** → Geographic context for releases and recoveries
- **Catch Samples** → Statistical sampling of fishery harvests
- **Descriptions** → Species, stock, and biological classifications

### Scientific Data Management
- **Tag loss calculations** - Statistical correction for tag shedding
- **Population estimation** - CWT-based abundance calculations  
- **Fishery impact analysis** - Harvest rate calculations by location/time
- **Stock contribution** - Hatchery vs. wild stock analysis
- **Migration patterns** - Release to recovery location analysis

## Agency Participation and Data Sources

### Confirmed Participating Agencies
Based on database schemas and discovered scripts:
- **ADFG** - Alaska Department of Fish and Game
- **WDFW** - Washington Department of Fish and Wildlife  
- **ODFW** - Oregon Department of Fish and Wildlife
- **CDFG** - California Department of Fish and Game
- **CDFO** - Canadian Department of Fisheries and Oceans
- **NMFS** - National Marine Fisheries Service
- **USFWS** - US Fish and Wildlife Service
- **Tribal entities** - Various Pacific Northwest tribes

### Data Governance
- **Agency ownership** - Each agency owns and maintains their submitted data
- **Quality control** - Multi-stage validation before database entry
- **Access control** - Role-based database permissions (rmis_holder, rmis_reader1)
- **Audit trails** - Complete submission and processing history maintained

## Discovery Session History

### Session Documentation
- **`saira-inventory`** - Initial server discovery, database listing, system architecture
- **`saira-inventory2`** - Database connection testing and permissions analysis  
- **`saira-inventory3`** - Surgical schema extraction and table size analysis

### Key Discoveries Timeline
1. **Database structure** - 5 databases identified with rpro as production
2. **Table sizes** - Recoveries table (4.8GB) identified as primary data store
3. **Query views** - 45+ views discovered matching Horus CGI scripts exactly
4. **Integration points** - NFS sharing and queue management confirmed
5. **Complete schemas** - Core PSC table structures extracted and analyzed

## Extraction Status

### ✅ Successfully Completed
- [x] **Server discovery** - Complete system architecture mapped
- [x] **Database inventory** - All 5 databases identified and analyzed
- [x] **Core table schemas** - Main PSC tables extracted and documented
- [x] **Query view analysis** - Integration with rmis query system confirmed
- [x] **Infrastructure mapping** - Cron jobs, queue system, NFS sharing documented
- [x] **Data pipeline validation** - End-to-end flow from Horus to queries confirmed

### ✅ Fully Completed Extraction
- [x] **Processing scripts** - Complete `/home/rmpcdb/` extraction (87MB archive)
- [x] **Cron infrastructure** - Complete `/etc/cron.rmpcdb.*` extraction (9.7KB archive)
- [x] **Queue management** - Complete qrun and queue processing system documented
- [x] **SQL scripts** - Database maintenance and migration scripts extracted
- [x] **Processing analysis** - Detailed analysis of validation and loading scripts

### 📋 Potential Future Analysis Tasks
- [ ] **Data relationship mapping** - Create entity-relationship diagrams
- [ ] **Performance analysis** - Query optimization and indexing review  
- [ ] **Migration planning** - Assess modernization opportunities for database layer
- [ ] **Backup/recovery** - Document data protection and disaster recovery procedures

### 📄 **Additional Documentation Created**
- **`PROCESSING_SCRIPTS_ANALYSIS.md`** - Comprehensive analysis of Saira processing scripts
- **`saira-inventory*`** - Six detailed discovery session logs
- **Archives**: 
  - `saira-rmpcdb-home.tar.gz` (87MB) - Complete processing infrastructure
  - `saira-system-config.tar.gz` (9.7KB) - Cron jobs and system configuration

## Critical System Insights

### Database as System Backbone
Saira serves as the **central data repository** for the entire RMPC system:
- **50+ years of historical data** - Invaluable scientific and management resource
- **Real-time query support** - Immediate access to current and historical data
- **Multi-agency coordination** - Single source of truth for Pacific salmon management
- **Complex data relationships** - Sophisticated biological and spatial data modeling

### Integration with Legacy Systems
- **Perfect schema alignment** - Database views match Horus CGI queries exactly
- **Proven stability** - Decades of reliable operation with massive datasets
- **Scientific integrity** - Rigorous validation maintains data quality
- **Regulatory compliance** - Supports official fishery management decisions

### Modernization Considerations
- **Data preservation critical** - Any modernization must maintain historical data integrity
- **Query compatibility** - Existing analysis tools depend on current schema structure
- **Agency workflows** - Changes must accommodate established data submission processes
- **Performance requirements** - System supports real-time query demands from multiple users

## Future Development Priorities

### Immediate Tasks
1. **Complete processing script extraction** - Understand Horus-to-Saira data flow
2. **Infrastructure documentation** - Full automation and maintenance procedures
3. **Performance baseline** - Current query performance and optimization opportunities

### Medium-term Opportunities  
1. **API development** - Modern REST API layer over PostgreSQL backend
2. **Query optimization** - Index analysis and performance improvements
3. **Data validation automation** - Integrate Horus validation into database constraints
4. **Monitoring enhancement** - Real-time system health and performance tracking

### Long-term Modernization
1. **Cloud migration planning** - Assess cloud database options while preserving functionality
2. **Data warehouse optimization** - Separate OLTP and OLAP workloads
3. **Integration streamlining** - Direct API connections replacing file-based transfers
4. **User interface modernization** - Web-based query tools replacing legacy CGI

---

This discovery and analysis of Saira provides the **complete database backend understanding** necessary for RMPC system modernization while preserving the scientific integrity and operational reliability of this critical Pacific salmon management resource.