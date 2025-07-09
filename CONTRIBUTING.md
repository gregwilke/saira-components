# Contributing to RMPC Saira Components

## Overview

This repository contains extracted components from the production Saira server (`saira.psmfc.org`) - the database and processing backbone of the Regional Mark Processing Center (RMPC) system.

**⚠️ IMPORTANT**: This repository contains **analysis and documentation** of a live production system. Any changes to the actual production system must follow PSMFC operational procedures.

## Repository Purpose

This repository serves to:
- **Preserve**: Complete extraction of production processing infrastructure
- **Document**: Comprehensive analysis of database and processing systems
- **Enable**: Development environment setup and modernization planning
- **Archive**: Historical preservation of 50+ years of fisheries management code

## Types of Contributions

### ✅ **Welcomed Contributions**
- **Documentation Improvements**: Clarify existing analysis and documentation
- **Analysis Enhancement**: Additional insights into processing scripts and database structure
- **Development Environment**: Docker setups, local development tools
- **Modernization Planning**: Assessment of upgrade paths and integration strategies
- **Bug Fixes**: Corrections to documentation or analysis errors

### ⚠️ **Restricted Contributions**
- **Production Changes**: No direct modifications to production system components
- **Credential Updates**: Production passwords and access credentials must be handled via PSMFC procedures
- **System Configuration**: Live system cron jobs, database settings, and operational parameters

## Contribution Process

### 1. **Understanding the System**
Before contributing, please read:
- `REPOSITORY_README.md` - Repository overview
- `README.md` - Comprehensive system analysis
- `docs/PROCESSING_SCRIPTS_ANALYSIS.md` - Detailed processing script analysis

### 2. **Types of Changes**

#### **Documentation Updates**
- Fix typos, clarify explanations, improve formatting
- Add additional analysis or insights
- Create diagrams or visualizations of system architecture

#### **Development Tools**
- Docker configurations for local development
- Scripts for archive extraction and analysis
- Development environment setup automation

#### **Analysis and Research**
- Performance analysis of processing scripts
- Security assessment of current implementation
- Integration planning for modernization efforts

### 3. **Submission Guidelines**

#### **Branch Naming**
- `docs/description` - Documentation improvements
- `analysis/description` - Additional system analysis
- `dev-tools/description` - Development environment tools
- `modernization/description` - Modernization planning

#### **Commit Messages**
Use clear, descriptive commit messages:
```
docs: clarify database schema relationships in README
analysis: add performance characteristics to processing scripts
dev-tools: add Docker setup for local PostgreSQL testing
modernization: assess API integration points for validation pipeline
```

#### **Pull Request Process**
1. **Fork** the repository
2. **Create** a feature branch with descriptive name
3. **Make** your changes with clear commit messages
4. **Test** any scripts or tools you've added
5. **Submit** pull request with detailed description
6. **Respond** to review feedback promptly

## Documentation Standards

### **File Organization**
- **Keep** existing directory structure
- **Use** clear, descriptive filenames
- **Organize** related content together
- **Reference** source files and discovery sessions when relevant

### **Writing Style**
- **Be Clear**: Technical accuracy with accessible explanations
- **Be Comprehensive**: Include context and background
- **Be Specific**: Reference exact files, line numbers, and system components
- **Be Respectful**: This is a live production system serving critical fisheries management

### **Code and Script Documentation**
- **Comment** complex logic and business rules
- **Explain** integration points and dependencies
- **Document** environment requirements and setup steps
- **Reference** original extraction sources

## Development Environment

### **Local Setup**
The repository includes archives that can be extracted for local analysis:
```bash
# Extract processing scripts
tar -xzf archives/saira-rmpcdb-home.tar.gz

# Extract system configuration  
tar -xzf archives/saira-system-config.tar.gz

# Extract database schemas
tar -xzf archives/saira-database-schemas.tar.gz
```

### **Analysis Tools**
- **Database Tools**: PostgreSQL client for schema analysis
- **Script Analysis**: Perl environment for processing script examination
- **Archive Tools**: Standard Unix tools for archive extraction and examination

## Security Considerations

### **Sensitive Information**
- **Production Credentials**: Handle according to PSMFC security policies
- **System Access**: Production server access requires proper authorization
- **Data Protection**: Pacific salmon data is scientifically and economically critical

### **Responsible Disclosure**
If you discover security vulnerabilities:
1. **Do NOT** create public issues or pull requests
2. **Contact** PSMFC system administrators directly
3. **Follow** responsible disclosure practices

## Integration with RMPC System

### **Related Repositories**
This repository is part of the complete RMPC system:
- **rmis**: Legacy PHP query system
- **rmis-files**: Modern JavaScript upload interface  
- **rmis-api**: Modern NodeJS upload API
- **horus-components**: PSC validation system components
- **saira-components**: This repository (database and processing)

### **System Dependencies**
- **Horus Integration**: NFS file sharing, shared logging
- **Database Dependencies**: PostgreSQL 16+, specific user permissions
- **Processing Pipeline**: Integration with validation queue and cron system

## Questions and Support

### **Technical Questions**
- **Repository Issues**: Use GitHub issues for documentation and analysis questions
- **System Architecture**: Reference comprehensive documentation in repository
- **Development Setup**: Check existing development tools and documentation

### **Production System Questions**
- **PSMFC Contact**: For production system access and operational questions
- **System Maintainer**: Jim Longwill (JRL) - Primary RMIS maintainer
- **Admin Contact**: rmpcdb.admin@psmfc.org

## Code of Conduct

### **Professional Standards**
- **Respectful Communication**: Professional and constructive interactions
- **System Responsibility**: Understanding this supports critical fisheries management
- **Collaborative Approach**: Working together to preserve and improve system understanding

### **Technical Standards**
- **Accuracy**: Ensure technical accuracy in documentation and analysis
- **Completeness**: Provide sufficient context and background
- **Maintainability**: Consider long-term maintenance and understanding

---

**Thank you for contributing to the preservation and modernization of this critical Pacific salmon management infrastructure!**

## Getting Started Checklist

- [ ] Read `REPOSITORY_README.md` and `README.md`
- [ ] Review `docs/PROCESSING_SCRIPTS_ANALYSIS.md`
- [ ] Understand the production system context and responsibilities  
- [ ] Set up local development environment if needed
- [ ] Identify specific contribution area (docs, analysis, dev-tools, etc.)
- [ ] Follow branch naming and commit message guidelines
- [ ] Submit pull request with clear description and context