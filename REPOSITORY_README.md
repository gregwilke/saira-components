# RMPC Saira Components

**Database and Processing Server Components for the Regional Mark Processing Center (RMPC)**

This repository contains all extracted components from the Saira server (`saira.psmfc.org`), which serves as the PostgreSQL database backend and processing engine for the RMPC system's Pacific salmon tracking and fisheries management operations.

## 🗄️ Repository Overview

Saira is the **database and processing backbone** of the RMPC system, handling:
- **PostgreSQL Database**: 50+ years of Pacific salmon data storage
- **Data Processing**: Perl-based validation and loading scripts  
- **Queue Management**: Automated processing pipeline
- **Integration**: NFS connections with Horus validation server

## 📁 Repository Structure

```
saira-components/
├── README.md                           # Original comprehensive analysis
├── REPOSITORY_README.md                # This overview (for GitHub)
├── database/                           # Database structure and schemas
│   ├── schemas/                        # PostgreSQL table definitions
│   │   ├── recoveries_schema.txt       # Recovery data (4.8GB table)
│   │   ├── releases_schema.txt         # Release data (144MB table)
│   │   ├── catch_sample_schema.txt     # Catch sampling data
│   │   ├── locations_schema.txt        # Geographic reference data
│   │   └── descriptions_schema.txt     # Species/stock definitions
│   └── views/                          # Database view definitions
│       ├── query_ta1rec_view.txt       # Tag recovery analysis view
│       └── query_csv_rc_view.txt       # Recovery CSV export view
├── extracted-scripts/                  # Processing infrastructure
│   └── rmpcdb/                         # Complete /home/rmpcdb extraction
│       └── bin/                        # Production scripts
│           ├── load_psc.pl             # Main data loading script (25KB)
│           ├── runval.pl               # Validation orchestrator (11KB)
│           ├── rc_validate.pm          # Recovery validation (53KB)
│           ├── rl_validate.pm          # Release validation (60KB)
│           └── [50+ other scripts]     # Complete processing suite
├── archives/                           # Complete system extractions
│   ├── saira-rmpcdb-home.tar.gz        # 87MB - Complete processing infrastructure
│   ├── saira-system-config.tar.gz     # 9.7KB - Cron jobs and configuration
│   └── saira-database-schemas.tar.gz   # Database schema archive
├── discovery-logs/                     # Extraction session documentation
│   ├── saira-inventory                 # Initial database discovery
│   ├── saira-inventory2                # Connection testing and permissions
│   ├── saira-inventory3                # Surgical schema extraction
│   ├── saira-inventory5                # Processing scripts extraction
│   └── saira-inventory6                # Infrastructure and cron extraction
└── docs/                              # Analysis and documentation
    └── PROCESSING_SCRIPTS_ANALYSIS.md  # Detailed processing script analysis
```

## 🎯 Key Components

### **PostgreSQL Database Backend**
- **5 Databases**: rpro (production), rrep (reporting), rdev1-3 (development)
- **Core Tables**: recoveries_042 (4.8GB), releases_042 (144MB), catch_sample_042, locations_042
- **45+ Query Views**: Perfect integration with Horus CGI query system
- **Historical Scope**: 50+ years of Pacific salmon data (y1973_est → y2025_est+)

### **Processing Infrastructure**
- **`load_psc.pl`**: Main data loading orchestrator with 12-parameter interface
- **Validation Modules**: Complete PSC format validation (Perl modules)
- **Queue System**: `qrun` processes validation queue every minute
- **Automation**: Comprehensive cron system for nightly/monthly operations

### **Integration Points**
- **NFS Integration**: `/net/horus/usr/home/` - Direct access to Horus agency directories
- **Shared Logging**: `/net/horus/usr/pub_horus/logs/` - Common logging with Horus
- **Environment Config**: Complete integration variables for Horus-Saira coordination

## 🔧 Data Processing Pipeline

### **Processing Workflow**
```
1. File Detection: qrun monitors for new submissions
2. Validation: runval.pl → load_psc.pl → validation modules  
3. Database Load: Validated data → PostgreSQL tables
4. Reporting: Automated data integrity reports and status updates
```

### **Command Interface**
```bash
# Main processing command structure:
load_psc.pl db_name file_type agency year trans stage val move midyr fullset format file_name

# Example:
load_psc.pl rpro rc ADFG 2024 N Y Y Y N N 4.2 /home/rmis/up/rc_ADFG_2024.csv
```

## 📊 System Specifications

### **Database Scale**
- **Primary Table**: recoveries_042 (4.8GB, millions of recovery records)
- **Release Data**: releases_042 (144MB, comprehensive tagging data)
- **Geographic Data**: locations_042 (32MB, Pacific Northwest locations)
- **Multi-Agency**: ADFG, WDFW, ODFW, CDFO, NMFS, USFWS, tribal entities

### **Processing Characteristics**
- **Real-time Processing**: Minute-by-minute queue monitoring
- **Validation Rigor**: 50+ validation checks per data type  
- **Scientific Precision**: Species-specific biological limits and cross-referencing
- **Audit Trail**: Complete processing logs and data integrity reporting

## 🔗 Integration with RMPC System

### **Server Architecture**
- **Horus**: Web server (validation and query interface)
- **Phish**: API server (modern upload interface)  
- **Saira**: Database server (this repository - processing backend)

### **Data Flow Integration**
```
Upload (Phish) → Validation (Horus) → Processing (Saira) → Query (Horus)
```

## 🛠️ Development and Analysis

### **Getting Started**
1. **Database Analysis**: Start with `database/schemas/` for table structures
2. **Processing Logic**: Examine `extracted-scripts/rmpcdb/bin/` for core scripts
3. **Integration Understanding**: Review `docs/PROCESSING_SCRIPTS_ANALYSIS.md`

### **Key Files for Developers**
- **Main Processor**: `extracted-scripts/rmpcdb/bin/load_psc.pl`
- **Database Schema**: `database/schemas/recoveries_schema.txt` (primary table)
- **Processing Analysis**: `docs/PROCESSING_SCRIPTS_ANALYSIS.md`
- **Discovery Logs**: `discovery-logs/saira-inventory5` (processing extraction)

## 🔐 Security and Operations

### **Production Environment**
- **Server**: saira.psmfc.org (Ubuntu 22+, PostgreSQL 16)
- **Database Access**: `rmis_holder` user with full production access
- **Monitoring**: Email notifications to `rmpcdb.admin@psmfc.org`
- **Automation**: Complete cron infrastructure for data processing

### **Data Integrity**
- **Validation Pipeline**: Multi-stage validation before database entry
- **Cross-referencing**: Tag codes validated against release records
- **Quality Reports**: 15 monthly automated data integrity reports
- **Audit Trails**: Complete processing history maintained

## 📈 Scientific and Economic Impact

### **Mission Critical System**
- **50+ Years**: Historical Pacific salmon tracking data
- **Multi-Agency Coordination**: Unified data management across Pacific Northwest
- **Regulatory Support**: Data supports official fisheries management decisions
- **Research Foundation**: Scientific analysis of salmon populations and migration

## 🚀 Modernization Opportunities

### **Current State**
- **Proven Stability**: Decades of reliable operation with massive datasets
- **Complex Business Logic**: Sophisticated validation rules and processing workflows
- **Legacy Technology**: Perl-based scripts with extensive domain knowledge

### **Future Considerations**
- **API Integration**: Modernize file-based processing with REST APIs
- **Containerization**: Docker-based deployment for development consistency
- **Performance Optimization**: Parallel processing for large dataset validation
- **Cloud Migration**: Assessment of cloud database options

## 📋 Related Repositories

Part of the complete RMPC system:
- **rmis**: Legacy PHP query system
- **rmis-files**: Modern JavaScript upload interface
- **rmis-api**: Modern NodeJS upload API  
- **horus-components**: PSC validation system and web server components
- **saira-components**: This repository - database and processing backend

## 📞 Contact and Support

**System Maintainer**: Jim Longwill (JRL) - Primary RMIS maintainer (2006-present)  
**Organization**: Pacific States Marine Fisheries Commission (PSMFC)  
**Production Support**: rmpcdb.admin@psmfc.org

---

**This repository preserves the complete database and processing infrastructure for one of the most comprehensive Pacific salmon tracking systems in the world, supporting critical fisheries management decisions across the Pacific Northwest.**