# RMPC System - Saira Components

## Project Context
This is the **Saira Components** subproject of the larger RMPC System. Saira serves as the database and processing server in the three-server architecture (Horus, Phish, Saira).

## Parent Project
- **Main Repository**: `/Users/gregorywilke/Projects/github-work/rmpc-system/`
- **Main CLAUDE.md**: `../CLAUDE.md` (contains complete system context)
- **System Architecture**: Horus (web) → Phish (API) → **Saira (database/processing)**

## Saira Server Role
- **Primary Function**: PostgreSQL database server and legacy Perl processing scripts
- **Data Processing**: Validates and processes CWT (coded-wire tag) data from agency uploads
- **Database Management**: Stores and serves Pacific salmon tagging/recovery data
- **Legacy Scripts**: Perl-based validation and processing pipeline in `/home/rmpcdb/bin/`

## Repository Structure
```
saira-components/
├── archives/                    # Extracted server components
│   ├── saira-database-schemas.tar.gz
│   ├── saira-rmpcdb-home.tar.gz
│   └── saira-system-config.tar.gz
├── database/                    # Database schema documentation
│   ├── schemas/                 # Table schemas (catch_sample, descriptions, etc.)
│   └── views/                   # Database views
├── discovery-logs/              # Server inventory logs
├── docs/                        # Analysis documentation
├── extracted-scripts/           # Extracted Perl processing scripts
│   └── rmpcdb/
│       └── bin/                 # Legacy validation/processing scripts
└── README.md                    # Repository documentation
```

## Current Status
- ✅ **Server Discovery**: Complete system inventory and extraction
- ✅ **Database Schema**: Documented main tables and relationships
- ✅ **Script Extraction**: Legacy Perl processing scripts extracted
- ⏳ **System Integration**: Understanding data flow with Horus/Phish
- ⏳ **Modernization Planning**: Docker development environment

## Key Components

### Database Tables
- **releases**: Tag release data from hatcheries
- **recoveries**: Tag recovery data from fisheries
- **locations**: Geographic and facility information
- **catch_sample**: Fishery catch sampling data
- **descriptions**: Data submission descriptions

### Processing Scripts
- **Validation**: Data format and content validation
- **Loading**: Database loading and transformation
- **Reporting**: Data quality and summary reports
- **Backup**: Automated backup and archival

## Development Context
- **Component Independence**: Can be developed separately from other RMPC components
- **Legacy Integration**: Must maintain compatibility with existing Perl scripts
- **Data Pipeline**: Receives validated data from Horus processing, serves data to Phish API
- **Production Safety**: No direct production server changes during development

## Common Commands

### Database Schema Exploration
```bash
# View table schemas
ls database/schemas/

# View database views
ls database/views/
```

### Processing Script Analysis
```bash
# View extracted Perl scripts
ls extracted-scripts/rmpcdb/bin/

# View processing analysis
cat docs/PROCESSING_SCRIPTS_ANALYSIS.md
```

### Archive Extraction
```bash
# Extract server components for analysis
cd archives/
tar -tzf saira-database-schemas.tar.gz
tar -tzf saira-rmpcdb-home.tar.gz
tar -tzf saira-system-config.tar.gz
```

## Related Repositories
- **rmis-api**: Modern NodeJS API server (consumes Saira data)
- **rmis-files**: Modern upload interface (feeds data to Saira)
- **rmis**: Legacy PHP query system (queries Saira database)
- **horus-components**: Validation and processing bridge

## Important Notes
- **Database Server**: PostgreSQL with custom schema for CWT data
- **Legacy Scripts**: Perl-based, must maintain compatibility
- **Data Integrity**: Critical for Pacific salmon management decisions
- **Multi-Agency**: Serves data for multiple fisheries management agencies

## Next Steps
1. Create Docker development environment for Saira database
2. Document complete data flow from upload to query
3. Plan incremental modernization of Perl processing scripts
4. Integrate with modern upload system (rmis-files → rmis-api)