# Saira Server Archives

This directory contains complete extractions from the Saira production server (`saira.psmfc.org`).

## 📦 Archive Contents

### **`saira-rmpcdb-home.tar.gz`** (87MB)
**Complete processing infrastructure from `/home/rmpcdb/`**

**Contents:**
- **Production Scripts**: `bin/` directory with active processing scripts
- **Legacy Archives**: `bin-041/` with PSC v4.1 format scripts and version history
- **Development Scripts**: `wrk/` directory with testing and development code
- **Database Administration**: `dba/` directory with database management scripts

**Key Components:**
- `bin/load_psc.pl` (25KB) - Main data loading orchestrator
- `bin/runval.pl` (11KB) - Validation wrapper with logging
- `bin/rc_validate.pm` (53KB) - Recovery data validation module
- `bin/rl_validate.pm` (60KB) - Release data validation module
- `bin/cs_validate.pm`, `bin/lc_validate.pm`, `bin/dd_validate.pm` - Other validation modules
- 50+ processing, reporting, and location validation scripts

**Extraction Date:** July 8, 2025  
**Source:** `/home/rmpcdb/` on saira.psmfc.org  
**Extraction Method:** `sudo tar -czf saira-rmpcdb-home.tar.gz -C /home rmpcdb`

### **`saira-system-config.tar.gz`** (9.7KB)
**System configuration and automation infrastructure**

**Contents:**
- **Cron Jobs**: `/etc/cron.rmpcdb.*` directories (daily, weekly, monthly, yearly)
- **Queue Management**: `/usr/local/sbin/qrun` - Runs every minute
- **System Configuration**: Environment and automation setup

**Key Components:**
- `cron.rmpcdb.monthly/` - 15 data integrity reports (hatchery checks, weight/length validation)
- `cron.rmpcdb.weekly/` - Weekly PSC data posting (DD, LC, RL formats)
- `qrun` - Queue processor for validation pipeline
- System configuration files and automation scripts

**Extraction Date:** July 8, 2025  
**Source:** `/etc/cron*`, `/usr/local/sbin/qrun*`, system configuration files  
**Extraction Method:** `sudo tar -czf saira-system-config.tar.gz --ignore-failed-read /etc/cron* /usr/local/sbin/qrun*`

### **`saira-database-schemas.tar.gz`**
**PostgreSQL database schema definitions**

**Contents:**
- Complete table schemas for all PSC data types
- Database view definitions for query system integration
- Index definitions and table relationships

**Key Schemas:**
- `recoveries_042` - Primary recovery data table (4.8GB in production)
- `releases_042` - Release and tagging data (144MB in production)
- `catch_sample_042` - Fishing harvest sampling data
- `locations_042` - Geographic reference data
- `descriptions_042` - Species and stock definitions

**Extraction Date:** July 8, 2025  
**Source:** PostgreSQL `rpro` database on saira.psmfc.org  
**Extraction Method:** Surgical schema extraction targeting PSC tables

## 🔐 Security and Usage Notes

### **Production Credentials**
⚠️ **WARNING**: These archives may contain production system credentials and configuration. Handle according to PSMFC security policies.

**Known Sensitive Information:**
- Database connection credentials in environment configurations
- System paths and NFS mount points
- Email addresses and notification configurations

### **Extraction Context**
- **Purpose**: System analysis and modernization planning
- **Scope**: Complete infrastructure extraction for development environment creation
- **Production Impact**: Zero - read-only extractions with no system modifications
- **Authorization**: Authorized PSMFC personnel access

## 🛠️ Usage Instructions

### **Extracting Archives**
```bash
# Extract complete processing infrastructure
tar -xzf saira-rmpcdb-home.tar.gz

# Extract system configuration
tar -xzf saira-system-config.tar.gz

# Extract database schemas
tar -xzf saira-database-schemas.tar.gz
```

### **Development Environment Setup**
1. **Extract Archives**: Use commands above to extract components
2. **Review Scripts**: Examine `rmpcdb/bin/` for processing logic
3. **Database Setup**: Use schemas in `database/schemas/` for local PostgreSQL setup
4. **Environment Config**: Reference system config for integration requirements

### **Analysis and Research**
- **Processing Logic**: Focus on `rmpcdb/bin/load_psc.pl` and validation modules
- **Database Structure**: Review schemas for data relationships and constraints
- **Automation**: Examine cron configurations for operational procedures
- **Integration**: Study environment variables and shared resource configurations

## 📋 Archive Integrity

### **Checksums and Verification**
Generate checksums for archive verification:
```bash
sha256sum *.tar.gz > archive_checksums.txt
```

### **Archive Creation Log**
Detailed extraction logs are available in `../discovery-logs/`:
- `saira-inventory5` - Processing scripts extraction session
- `saira-inventory6` - System configuration extraction session

### **Completeness Verification**
Each archive represents a complete extraction of its target system area:
- **Processing Scripts**: 100% of `/home/rmpcdb/` directory structure
- **System Config**: All automation and cron configurations
- **Database Schemas**: Complete PSC table and view definitions

## 🔗 Integration with Discovery Process

### **Discovery Timeline**
1. **Initial Discovery**: Database structure and connection analysis
2. **Schema Extraction**: Surgical extraction of PSC table schemas
3. **Processing Scripts**: Complete `/home/rmpcdb/` extraction
4. **System Configuration**: Cron jobs and automation infrastructure
5. **Analysis Phase**: Detailed script analysis and documentation

### **Related Documentation**
- `../discovery-logs/` - Complete extraction session logs
- `../docs/PROCESSING_SCRIPTS_ANALYSIS.md` - Detailed analysis of extracted scripts
- `../README.md` - Comprehensive system analysis and integration context

---

**These archives represent the complete database and processing infrastructure for the RMPC system - a critical Pacific salmon management system supporting 50+ years of fisheries research and regulatory decisions.**