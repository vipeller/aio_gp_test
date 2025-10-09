# Test Configuration for Fabric Eventhouse Helper PyApp

## Test Coverage Summary

Total Tests: **45**

### test_eventhouse_manager.py (30 tests)
**TestEventhouseManager (25 tests)**
- Authentication tests (3)
- Table creation tests (3) 
- Update policy tests (2)
- Kusto function tests (2)
- Data type mapping tests (1)
- Initialization tests (2)
- Entity type definitions loading tests (3)
- YAML mappings loading tests (2)
- Type mappings parsing tests (3)
- Entity mappings creation tests (2)
- Entity mappings processing tests (2)

**TestEventhouseManagerIntegration (5 tests)**
- Complete setup workflow tests covering authentication, YAML/JSON input, error scenarios

### test_main.py (15 tests)
**TestMainFunctions (13 tests)**
- CLI argument parsing and command execution
- YAML file input testing
- JSON command line input testing
- Multiple type mappings handling
- Error scenarios and validation
- Help and invalid command handling

**TestMainExceptionHandling (2 tests)**
- Exception handling and user interruption scenarios

## Key Test Features

✅ **Complete Code Coverage**: Tests cover all major functions and methods
✅ **Mock-based Testing**: Uses unittest.mock to isolate units and avoid external dependencies
✅ **Error Scenario Testing**: Covers authentication failures, file not found, invalid JSON/YAML
✅ **Integration Testing**: Tests complete workflows from CLI to table creation
✅ **Input Validation**: Tests both YAML file and JSON command line inputs
✅ **Edge Cases**: Tests duplicate detection, missing fields, invalid formats

## Running Tests

```bash
# Run all tests
.\.venv\Scripts\python.exe -m pytest tests/ -v

# Run specific test file
.\.venv\Scripts\python.exe -m pytest tests/test_eventhouse_manager.py -v

# Run with coverage (if coverage installed)
.\.venv\Scripts\python.exe -m pytest tests/ --cov=src --cov-report=html
```

## Test Environment
- **Framework**: unittest with pytest runner
- **Mocking**: unittest.mock for external dependencies
- **Azure SDK**: Mocked to avoid requiring actual Azure credentials
- **File Operations**: Mocked to avoid requiring actual files
