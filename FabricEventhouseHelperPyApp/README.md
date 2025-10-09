# Fabric Eventhouse Helper PyApp

A CLI tool to help setup the Fabric Event House for Fabric Ontology with dynamic table creation, update policies, and data transformation functions.

## Overview

This application automates the setup of Microsoft Fabric Eventhouse with:
- **AIORawData table** for raw data ingestion
- **Dynamic entity tables** based on EntityTypeDefinitions.json
- **Update policies** for automatic data transformation
- **MoveDataByType function** for data processing

## Features

✅ **Multiple Input Methods**: YAML files or JSON command line arguments  
✅ **Dynamic Table Creation**: Tables generated from EntityTypeDefinitions.json  
✅ **Automatic Update Policies**: All entity tables get update policies  
✅ **Data Type Mapping**: Converts entity types to Kusto data types  
✅ **Duplicate Column Detection**: Prevents schema conflicts  
✅ **Comprehensive Logging**: Detailed operation logs with error handling  
✅ **Verbose Mode**: Configurable debug output with `--verbose` flag  
✅ **Azure Authentication**: Multiple authentication methods (Azure CLI, Device Code)  
✅ **Enhanced Authentication Error Handling**: Specific guidance for Azure CLI login issues  
✅ **Resource Management**: Context manager support for proper cleanup  
✅ **Constants Optimization**: Centralized configuration constants  
✅ **Enhanced Error Handling**: Detailed HTTP response logging and error context  
✅ **Production Ready**: Validated with real Azure Fabric Eventhouse clusters

## Installation

### Prerequisites
- Python 3.10+
- Azure CLI (optional, for authentication)
- Access to Microsoft Fabric Eventhouse

### Install Dependencies
```bash
# Clone the repository
git clone <repository-url>
cd FabricEventhouseHelperPyApp

# Create virtual environment
python -m venv .venv

# Activate virtual environment
# Windows
.\.venv\Scripts\activate
# Linux/macOS
source .venv/bin/activate

# Install the package
pip install -e .
```

## Usage

### Command Line Interface

```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --log-file "setup.log" \
  [--yaml-file "mappings.yaml" | --type-mappings JSON...] \
  [--verbose]
```

### Input Methods

#### 1. YAML File Input

Create a YAML file with type mappings:

```yaml
# sample_mappings.yaml
type_mappings:
  - typeRef: "opcfoundation.org/UA/Pumps;i=1043"
    namespace: "AdditiveManufacturing"
    entity_name: "EquipmentAMType"
  - typeRef: "opcfoundation.org/UA/Pumps;i=1044"
    namespace: "AdditiveManufacturing"
    entity_name: "MachineIdentificationAMType"
  - typeRef: "opcfoundation.org/UA/Pumps;i=1050"
    namespace: "Glass_Flat"
    entity_name: "SealingMaterialType"
```

Run with YAML file:
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --log-file "setup.log" \
  --yaml-file "sample_mappings.yaml"
```

**With verbose logging:**
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --log-file "setup.log" \
  --yaml-file "sample_mappings.yaml" \
  --verbose
```

#### 2. JSON Command Line Input

**Single Mapping:**
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --log-file "setup.log" \
  --type-mappings '{"typeRef":"opcfoundation.org/UA/Pumps;i=1043","namespace":"AdditiveManufacturing","entity_name":"EquipmentAMType"}'
```

**Multiple Mappings:**
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --log-file "setup.log" \
  --type-mappings '{"typeRef":"opcfoundation.org/UA/Pumps;i=1043","namespace":"AdditiveManufacturing","entity_name":"EquipmentAMType"}' \
  --type-mappings '{"typeRef":"opcfoundation.org/UA/Pumps;i=1044","namespace":"AdditiveManufacturing","entity_name":"MachineIdentificationAMType"}'
```

> **Note**: Use single quotes (`'`) around JSON strings in PowerShell to avoid escaping issues.

## Architecture

### Core Components

1. **EventhouseManager** (`eventhouse.py`)
   - Main orchestration class with context manager support
   - Handles authentication, table creation, and update policies
   - Processes entity mappings and creates schemas
   - Centralized constants for maintainability
   - Enhanced error handling with detailed HTTP response logging

2. **CLI Interface** (`main.py`)
   - Command line argument parsing with improved validation
   - Input validation and enhanced error handling
   - Logging configuration with proper resource cleanup
   - Support for keyboard interrupt handling

3. **Entity Type Definitions** (`EntityTypeDefinitions.json`)
   - Schema definitions for all entity types
   - Property and timeseries property definitions
   - Data type mappings

### Data Flow

1. **Authentication**: Azure CLI or Device Code authentication
2. **Input Processing**: Parse YAML file or JSON command line arguments
3. **Schema Generation**: Match input to EntityTypeDefinitions.json
4. **Table Creation**:
   - Create AIORawData table first
   - Create MoveDataByType function
   - Create entity tables with generated schemas
   - Set update policies for all entity tables

### Generated Resources

#### AIORawData Table
```kusto
.create table AIORawData (
    ['key']: string, 
    value: string, 
    topic: string, 
    ['partition']: int, 
    offset: long, 
    timestamp: datetime, 
    timestampType: int, 
    headers: dynamic, 
    ['id']: string, 
    source: string, 
    ['type']: string, 
    subject: string, 
    ['time']: string, 
    ['data']: string
)
```

#### MoveDataByType Function
Transforms raw data from AIORawData into structured entity tables based on typeRef matching.

#### Entity Tables
- **Naming**: `{namespace}_{entity_name}` (e.g., `AdditiveManufacturing_EquipmentAMType`)
- **Schema**: Based on EntityTypeDefinitions.json properties
- **Standard Fields**: All tables include `Identifier:string` and `Timestamp:datetime`
- **Update Policy**: Automatically set to use MoveDataByType function

### Best Practices

### Performance Optimization
- **Batch Operations**: Multiple type mappings in a single execution are more efficient
- **Resource Management**: Use context managers when integrating with other Python code:
  ```python
  with EventhouseManager(cluster_url, database, log_file, verbose=True) as manager:
      manager.authenticate()
      manager.setup_tables_from_input(type_mappings=mappings)
  ```
- **Logging**: Use file logging for production deployments to capture full execution details
- **Verbose Mode**: Use `--verbose` flag for debugging but disable for production for cleaner output

### Input Method Selection
- **YAML files**: Best for complex configurations and version control
- **JSON CLI**: Ideal for automation scripts and CI/CD pipelines
- **Mixed approach**: Combine YAML base configuration with CLI overrides

### Error Handling
- Always check authentication before running large batches
- Use `--verbose` flag for debugging connectivity issues
- Review log files for detailed error context and HTTP responses
- **Enhanced Authentication Error Detection**: The tool now detects specific Azure CLI authentication failures and provides actionable guidance
- **KustoAuthenticationError Handling**: Authentication errors are properly caught and re-raised with user-friendly messages

### Production Deployment
- Validate configurations in non-production environments first
- Use Azure CLI authentication for automated deployments
- Monitor execution logs for performance metrics and errors

## Command Line Options

### Required Arguments
- `--cluster`: Eventhouse Query URI (Kusto cluster URL)
- `--database`: Database name

### Input Methods (choose one)
- `--yaml-file`: Path to YAML file containing type mappings
- `--type-mappings`: JSON format mappings (can specify multiple)

### Optional Arguments
- `--log-file`: Log file path for detailed operation logs
- `--verbose`: Enable verbose debug output

### Verbose Mode Benefits

The `--verbose` flag provides comprehensive debugging information useful for:

**Development and Testing:**
- See exact Kusto commands being executed
- Monitor HTTP connections and responses
- Track authentication flow details
- Debug schema generation logic

**Troubleshooting:**
- Detailed error messages with full context
- HTTP response codes and headers
- Network connection diagnostics
- Authentication failure root cause analysis

**Examples:**

**Normal Operation (Clean Output):**
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --yaml-file "mappings.yaml"
```

**Verbose Operation (Debug Output):**
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --cluster "https://your-cluster.kusto.fabric.microsoft.com/" \
  --database "YourDatabase" \
  --yaml-file "mappings.yaml" \
  --verbose
```

## Configuration

### Authentication
The tool supports multiple authentication methods:
1. **Azure CLI** (preferred): `az login`
2. **Device Code**: Interactive browser authentication

### Logging
Configurable logging levels and output destinations:
- **Console output**: Clean progress updates by default
- **Verbose mode**: Enable with `--verbose` flag for detailed debug information
- **File logging**: Detailed operations with UTF-8 encoding (always comprehensive)
- **Error logging**: HTTP response details and debug context
- **Automatic resource management**: Log file cleanup and proper resource handling

#### Logging Levels
- **Default mode** (without `--verbose`): Shows only INFO, WARNING, and ERROR messages
- **Verbose mode** (with `--verbose`): Shows all DEBUG messages including:
  - Executed Kusto commands
  - HTTP connection details
  - Authentication steps
  - Response objects
  - Detailed error information

### Data Type Mapping
Entity types are automatically mapped to Kusto types:
- `Number` → `double`
- `Boolean` → `boolean`
- `String` → `string`
- `Object` → `dynamic`
- `DateTime` → `datetime`
- Default → `string`

## Testing

### Run Tests
```bash
# Install test dependencies
pip install pytest

# Run all tests
pytest tests/ -v

# Run specific test file
pytest tests/test_eventhouse_manager.py -v

# Run with coverage
pytest tests/ --cov=src --cov-report=html
```

### Test Coverage
- **52 total tests** covering all major functionality
- **Unit tests** for EventhouseManager class methods
- **Integration tests** for complete workflows  
- **CLI tests** for argument parsing and command execution
- **Error scenario tests** for robust error handling
- **Authentication tests** for Azure CLI error handling and fallback scenarios

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Ensure Azure CLI is installed and logged in: `az login`
   - Check cluster URL format
   - Verify permissions to the Fabric workspace
   - **Enhanced Error Guidance**: The tool now provides specific guidance for Azure CLI authentication issues:
     ```
     ❌ Azure CLI authentication failed!
     🔧 Azure CLI Authentication Issue:
     1. Run: az login
     2. Ensure Azure CLI version 2.3.0+ is installed
     3. Check your subscription access
     4. Verify the cluster URL format
     ```

2. **Table Creation Errors**
   - Check entity type definitions match input mappings
   - Verify namespace and entity_name combinations exist
   - Review logs for specific Kusto error messages

3. **Large Entity Types**
   - Some entities have 1000+ properties (e.g., PAEFS.FilterSystemType: 7,881)
   - May cause performance issues or timeout
   - Consider filtering or splitting large entities

### Debug Mode
Enable verbose logging and comprehensive debugging:
```bash
python -m src.digitaloperations.fabriceventhousehelperpyapp.main setup-eventhouse \
  --verbose \
  --cluster "..." \
  --database "..." \
  --log-file "debug.log" \
  --yaml-file "mappings.yaml"
```

**Verbose mode provides:**
- All Kusto commands being executed
- HTTP connection details and responses
- Authentication flow details
- Response objects and timing information
- Enhanced error context and debugging information

### End-to-End Testing
The application has been validated with real Azure Fabric Eventhouse clusters:
- **Cluster**: Production Azure Fabric Eventhouse environments
- **Authentication**: Azure CLI integration tested and working
- **OPC UA Support**: Special characters in type references (e.g., `opcfoundation.org/UA/Pumps;i=1043`) handled correctly
- **Performance**: ~3 seconds for complete setup including multiple tables and policies

## Development

### Project Structure
```
FabricEventhouseHelperPyApp/
├── src/digitaloperations/fabriceventhousehelperpyapp/
│   ├── __init__.py
│   ├── main.py                     # CLI entry point
│   ├── eventhouse.py              # Core EventhouseManager class
│   └── EntityTypeDefinitions.json # Schema definitions
├── tests/
│   ├── test_eventhouse_manager.py # Unit tests
│   ├── test_main.py               # CLI tests
│   └── run_tests.py               # Test runner
├── pyproject.toml                 # Project configuration
└── sample_mappings.yaml           # Example input file
```

### Key Classes

#### EventhouseManager
- `authenticate()`: Handle Azure authentication with fallback methods
- `create_table()`: Create Kusto tables with enhanced validation
- `set_update_policy()`: Configure update policies with error handling
- `create_kusto_function()`: Create MoveDataByType function
- `setup_tables_from_input()`: Main orchestration method with resource management
- `__enter__()` / `__exit__()`: Context manager support for proper cleanup

### Contributing
1. Follow the existing code structure and patterns
2. Add unit tests for new functionality
3. Update documentation for API changes
4. Test with both YAML and JSON input methods
5. Validate changes with real Azure Fabric clusters when possible

## License

This project is part of the workload-digitaloperations repository.

## Version History

- **v0.3**: Enhanced verbose logging and authentication error handling
  - Added `--verbose` flag for configurable debug output
  - Enhanced authentication error detection with specific Azure CLI guidance
  - Improved KustoAuthenticationError handling with user-friendly messages  
  - Updated to 52 comprehensive tests including authentication scenarios
  - Better separation of INFO vs DEBUG logging levels
- **v0.2**: Enhanced with production optimizations
  - Context manager support for resource management
  - Centralized constants for maintainability
  - Enhanced error handling with HTTP response details
  - Production validation with real Azure clusters
  - Improved PowerShell compatibility for JSON inputs
- **v0.1**: Initial release with dynamic table creation and update policies
