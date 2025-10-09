#!/usr/bin/env python3

import json
import logging
import os
import yaml
from typing import List, Optional, Dict, Any
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
from azure.kusto.data.exceptions import KustoServiceError


# Custom exceptions
class AuthenticationError(Exception):
    """Raised when authentication to Azure fails"""
    pass


class AzureCliAuthenticationError(AuthenticationError):
    """Raised when Azure CLI authentication specifically fails"""
    pass


# Constants
DEFAULT_IDENTIFIER_FIELD = "Identifier:string"
DEFAULT_TIMESTAMP_FIELD = "Timestamp:datetime"
AIO_RAW_DATA_TABLE = "AIORawData"
AIO_RAW_DATA_SCHEMA = (
    "['key']: string, value: string, topic: string, ['partition']: int, "
    "offset: long, timestamp: datetime, timestampType: int, headers: dynamic, "
    "['id']: string, source: string, ['type']: string, subject: string, "
    "['time']: string, ['data']: string"
)

# Error messages
MSG_CLIENT_NOT_AUTH = "Client not authenticated. Call authenticate() first."
MSG_INVALID_TABLE_NAME = "Invalid table name or type reference provided."


class EventhouseManager:
    """
    A class to manage Fabric Eventhouse operations including table creation and update policies.
    """
    
    def __init__(self, cluster_url: str, database: str, log_file: Optional[str] = None, verbose: bool = False):
        """
        Initialize the EventhouseManager.
        
        Args:
            cluster_url: The Kusto cluster URL
            database: The database name
            log_file: Optional log file path. If None, logs to console.
            verbose: Enable debug-level logging
        """
        self.cluster_url = cluster_url
        self.database = database
        self.client = None
        
        # Configure logging
        self.logger = logging.getLogger(__name__)
        # Set logger level based on verbose parameter
        self.logger.setLevel(logging.DEBUG if verbose else logging.INFO)
        self.file_handler = None
        
        # Add file handler if log_file is specified
        if log_file:
            self.file_handler = logging.FileHandler(log_file, encoding='utf-8')
            # Set file handler level to match logger level
            self.file_handler.setLevel(logging.DEBUG if verbose else logging.INFO)
            formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
            self.file_handler.setFormatter(formatter)
            self.logger.addHandler(self.file_handler)
            self.logger.info(f"Logging to file: {log_file}")
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - ensures proper cleanup"""
        self.close_log_file()
        if self.client:
            # Clean up client resources if needed
            self.client = None
    
    def close_log_file(self):
        """Close the log file handler if it exists"""
        if self.file_handler:
            self.file_handler.close()
            self.logger.removeHandler(self.file_handler)
            self.file_handler = None
    
    def _log_detailed_error(self, operation: str, error: Exception) -> None:
        """
        Log detailed error information including HTTP response details.
        
        Args:
            operation: Description of the operation that failed
            error: The exception that was raised
        """
        self.logger.error(f"{operation} failed: {error}")
        self.logger.error(f"Exception type: {type(error).__name__}")
        self.logger.error(f"Exception details: {str(error)}")
        self.logger.error(f"Exception args: {error.args}")
        
        # Try to extract HTTP response details from various possible attributes
        response_found = False
        for attr in ['http_response', '_http_response', 'response', '_response']:
            if hasattr(error, attr):
                response = getattr(error, attr)
                if response:
                    self.logger.error(f"Found HTTP response in {attr}:")
                    if hasattr(response, 'status_code'):
                        self.logger.error(f"HTTP Status Code: {response.status_code}")
                    if hasattr(response, 'reason'):
                        self.logger.error(f"HTTP Reason: {response.reason}")
                    if hasattr(response, 'headers'):
                        self.logger.error(f"Response Headers: {dict(response.headers)}")
                    if hasattr(response, 'text'):
                        try:
                            self.logger.error(f"Response Content: {response.text}")
                        except Exception as resp_err:
                            self.logger.error(f"Could not read response text: {resp_err}")
                    elif hasattr(response, 'content'):
                        try:
                            content = response.content
                            if isinstance(content, bytes):
                                content = content.decode('utf-8', errors='replace')
                            self.logger.error(f"Response Content: {content}")
                        except Exception as resp_err:
                            self.logger.error(f"Could not read response content: {resp_err}")
                    response_found = True
                    break
        
        if not response_found:
            # Log all attributes of the exception for debugging
            self.logger.debug(f"Exception attributes: {[attr for attr in dir(error) if not attr.startswith('_')]}")
    
    def authenticate(self) -> bool:
        """
        Authenticate to the Kusto cluster using AAD authentication.
        Tries multiple authentication methods in order.
        
        Returns:
            bool: True if authentication successful, False otherwise
        """
        auth_methods = [
            ("Azure CLI", lambda: KustoConnectionStringBuilder.with_az_cli_authentication(self.cluster_url)),
            ("Device Code", lambda: KustoConnectionStringBuilder.with_aad_device_authentication(self.cluster_url))
        ]
        
        for method_name, kcsb_builder in auth_methods:
            try:
                self.logger.info(f"Attempting {method_name} authentication to cluster: {self.cluster_url}")
                kcsb = kcsb_builder()
                self.client = KustoClient(kcsb)
                self.logger.info(f"Successfully authenticated to cluster using {method_name}.")
                return True
            except Exception as e:
                self.logger.warning(f"{method_name} authentication failed: {str(e)}")
                self._log_detailed_error(f"{method_name} Authentication", e)
                continue
        
        self.logger.error("All authentication methods failed.")
        return False
    
    def create_table(self, table_name: str, schema: str) -> bool:
        """
        Create a table in the database.
        
        Args:
            table_name: Name of the table to create
            schema: Table schema definition
            
        Returns:
            bool: True if table created successfully, False otherwise
        """
        if not self.client:
            self.logger.error(MSG_CLIENT_NOT_AUTH)
            return False
        
        # Input validation
        if not table_name or not table_name.strip():
            self.logger.error("Table name cannot be empty")
            return False
        
        if not schema or not schema.strip():
            self.logger.error("Table schema cannot be empty")
            return False
            
        create_cmd = f".create table {table_name} ({schema})"
        
        try:
            self.logger.info(f"Creating table: {table_name}")
            self.logger.debug(f"Executing command: {create_cmd}")
            result = self.client.execute_mgmt(self.database, create_cmd)
            self.logger.info(f"Table {table_name} created successfully.")
            self.logger.debug(f"Create table result: {result}")
            return True
        except Exception as e:
            # Check if this is a KustoAuthenticationError and re-raise it
            if "KustoAuthenticationError" in str(type(e)) or "authentication" in str(e).lower():
                self.logger.error(f"Authentication error during table creation: {e}")
                raise e  # Re-raise authentication errors so they can be handled at main level
            else:
                self._log_detailed_error(f"Creating table {table_name}", e)
                return False
    
    def set_update_policy(self, table_name: str, type_ref: str) -> bool:
        """
        Set update policy for a table.
        
        Args:
            table_name: Name of the table
            type_ref: Type reference for the update policy
            
        Returns:
            bool: True if policy set successfully, False otherwise
        """
        if not self.client:
            self.logger.error(MSG_CLIENT_NOT_AUTH)
            return False
        
        # Input validation
        if not table_name or not table_name.strip():
            self.logger.error("Table name cannot be empty")
            return False
        
        if not type_ref or not type_ref.strip():
            self.logger.error("Type reference cannot be empty")
            return False
            
        if not table_name.isidentifier():
            self.logger.error(MSG_INVALID_TABLE_NAME)
            return False

        update_cmd = f""".alter table {table_name} policy update @'[{{"IsEnabled":true,"Source":"{AIO_RAW_DATA_TABLE}","Query":"MoveDataByType(\\\"{type_ref}\\\", \\\"{table_name}\\\")","IsTransactional":false}}]'"""
        
        try:
            self.logger.info(f"Setting update policy for table: {table_name}")
            self.logger.debug(f"Executing command: {update_cmd}")
            result = self.client.execute_mgmt(self.database, update_cmd)
            self.logger.info(f"Update policy set successfully for table {table_name}.")
            self.logger.debug(f"Update policy result: {result}")
            return True
        except KustoServiceError as e:
            self._log_detailed_error(f"Setting update policy for table {table_name}", e)
            return False
        except Exception as e:
            self._log_detailed_error(f"Setting update policy for table {table_name}", e)
            return False

    def create_kusto_function(self) -> bool:
        """
        Create the MoveDataByType function in the database.

        Returns:
            bool: True if function created successfully, False otherwise
        """
        if not self.client:
            self.logger.error(MSG_CLIENT_NOT_AUTH)
            return False

        function_cmd = """.create-or-alter function MoveDataByType(typeRef:string, targetTable:string)
{
    AIORawData
    | where type endswith typeRef
    | extend Identifier = tostring(split(subject, "/")[0])
    | extend Prefix = strcat_array(array_slice(split(subject, "/"), 1, -1), "_")
    | extend fixedJson = strcat(substring(data, 0, strlen(data) - 3), substring(data, strlen(data) - 2))
    | project Identifier, Prefix, fixedJson, data
    | extend ParsedData = parse_json(data)
    | extend keys = bag_keys(ParsedData)
    | where keys != ""
    | mv-expand telemetryName = keys
    | extend fieldDetails = ParsedData[tostring(telemetryName)]
    | extend telemetryValue = fieldDetails["Value"], Timestamp = todatetime(fieldDetails["ServerTimestamp"])
    | project Identifier, Timestamp, tostring(telemetryName), telemetryValue
    | summarize bag = make_bag(pack(tostring(telemetryName), telemetryValue)) by Identifier, Timestamp
    | evaluate bag_unpack(bag)
}"""

        try:
            self.logger.info("Creating MoveDataByType function")
            self.logger.debug(f"Executing command: {function_cmd}")
            result = self.client.execute_mgmt(self.database, function_cmd)
            self.logger.info("MoveDataByType function created successfully.")
            self.logger.debug(f"Create function result: {result}")
            return True
        except KustoServiceError as e:
            self._log_detailed_error("Creating MoveDataByType function", e)
            return False
        except Exception as e:
            self._log_detailed_error("Creating MoveDataByType function", e)
            return False
    
    def process_entity_mappings(self, entity_mappings: List[Dict[str, Any]]) -> Dict[str, bool]:
        """
        Process a list of entity mappings to create tables and set update policies.
        
        Args:
            entity_mappings: List of entity mapping dictionaries
            
        Returns:
            dict: Results of processing each mapping {table_name: success_status}
        """
        results = {}
        
        for mapping in entity_mappings:
            table_name = mapping["displayName"]
            type_ref = mapping["typeRef"]
            fields = mapping["fields"]
            
            # Build schema
            schema = ", ".join(fields)
            full_schema = schema
            
            # Create table
            table_created = self.create_table(table_name, full_schema)
            if not table_created:
                results[table_name] = False
                continue
            
            # Set update policy for all entity mappings (AIORawData is created separately)
            policy_set = self.set_update_policy(table_name, type_ref)
            results[table_name] = policy_set
        
        return results
    
    def _get_kusto_data_type(self, value_type: str) -> str:
        """Convert EntityTypeDefinitions value type to Kusto data type."""
        type_mapping = {
            "Number": "double",
            "Boolean": "boolean",
            "String": "string",
            "Object": "dynamic",
            "DateTime": "datetime"
        }
        return type_mapping.get(value_type, "string")
    
    def _load_entity_type_definitions(self, json_file_path: str) -> list:
        """Load entity type definitions from JSON file."""
        try:
            with open(json_file_path, 'r') as f:
                data = json.load(f)
                self.logger.info(f"Loaded entity type definitions from {json_file_path}")
                if isinstance(data, list):
                    return data
                else:
                    self.logger.error(f"Unexpected data format in {json_file_path}")
                    return []
        except FileNotFoundError:
            self.logger.error(f"EntityTypeDefinitions.json not found at {json_file_path}")
            return []
        except json.JSONDecodeError as e:
            self.logger.error(f"Invalid JSON in {json_file_path}: {e}")
            return []
    
    def _parse_type_mappings(self, type_mappings: List[str]) -> dict:
        """Parse command line type mappings in JSON format with typeRef, namespace, and entity_name."""
        mappings = {}
        for mapping in type_mappings:
            try:
                # Parse as JSON (structured format)
                if mapping.strip().startswith('{') and mapping.strip().endswith('}'):
                    mapping_dict = json.loads(mapping)
                    type_ref = mapping_dict.get('typeRef')
                    namespace = mapping_dict.get('namespace')
                    entity_name = mapping_dict.get('entity_name')
                    
                    if type_ref and namespace and entity_name:
                        # Map the typeRef to {namespace, entity_name}
                        mappings[type_ref] = {'namespace': namespace, 'entity_name': entity_name}
                        self.logger.info(f"Loaded structured mapping: {type_ref} -> {namespace}.{entity_name}")
                    else:
                        missing_fields = []
                        if not type_ref:
                            missing_fields.append("typeRef")
                        if not namespace:
                            missing_fields.append("namespace")
                        if not entity_name:
                            missing_fields.append("entity_name")
                        self.logger.warning(f"Invalid JSON mapping: missing {', '.join(missing_fields)} in mapping with typeRef='{type_ref}', namespace='{namespace}', entity_name='{entity_name}'")
                else:
                    self.logger.error(f"Invalid mapping format: {mapping}. Expected JSON format with typeRef, namespace, and entity_name")
            except json.JSONDecodeError as e:
                self.logger.error(f"Invalid JSON in type mapping '{mapping}': {e}")
        return mappings
    
    def _load_yaml_mappings(self, yaml_file: str) -> dict:
        """Load type mappings from YAML file."""
        try:
            with open(yaml_file, 'r') as f:
                data = yaml.safe_load(f)
                if isinstance(data, dict) and 'type_mappings' in data:
                    type_mappings = data['type_mappings']
                    
                    # Handle list format: [{"typeRef": "...", "namespace": "...", "entity_name": "..."}]
                    if isinstance(type_mappings, list):
                        mappings = {}
                        for mapping in type_mappings:
                            if isinstance(mapping, dict):
                                type_ref = mapping.get('typeRef')
                                namespace = mapping.get('namespace')
                                entity_name = mapping.get('entity_name')
                                
                                if type_ref and namespace and entity_name:
                                    # Map the typeRef to {namespace, entity_name}
                                    mappings[type_ref] = {'namespace': namespace, 'entity_name': entity_name}
                                    self.logger.info(f"Loaded mapping: {type_ref} -> {namespace}.{entity_name}")
                                else:
                                    missing_fields = []
                                    if not type_ref:
                                        missing_fields.append("typeRef")
                                    if not namespace:
                                        missing_fields.append("namespace")
                                    if not entity_name:
                                        missing_fields.append("entity_name")
                                    self.logger.warning(f"Invalid mapping in YAML: missing {', '.join(missing_fields)} in mapping with typeRef='{type_ref}', namespace='{namespace}', entity_name='{entity_name}'")
                            else:
                                self.logger.warning(f"Invalid mapping format in YAML: {mapping}")
                        return mappings
                    else:
                        self.logger.error(f"YAML file {yaml_file} 'type_mappings' must be a list")
                        return {}
                else:
                    self.logger.error(f"YAML file {yaml_file} does not contain 'type_mappings' key")
                    return {}
        except FileNotFoundError:
            self.logger.error(f"YAML file not found: {yaml_file}")
            return {}
        except yaml.YAMLError as e:
            self.logger.error(f"Invalid YAML in {yaml_file}: {e}")
            return {}
    
    def _create_entity_mappings_from_input(self, type_mappings: dict, entity_definitions: list) -> List[Dict[str, Any]]:
        """Create entity mappings using input type mappings and EntityTypeDefinitions."""
        entity_mappings = []
        
        # Process input mappings
        for type_ref, mapping_info in type_mappings.items():
            namespace = mapping_info['namespace']
            entity_name = mapping_info['entity_name']
            table_name = f"{namespace}_{entity_name}"  # Use underscore instead of dot for Kusto compatibility
            
            # Find matching entity definition
            entity_def = None
            
            for entity in entity_definitions:
                # Try to match by namespace and name if TypeReference not present
                entity_namespace = entity.get('Namespace', '')
                entity_name_def = entity.get('Name', '')
                if entity_namespace == namespace and entity_name_def == entity_name:
                    entity_def = entity
                    break
            
            if not entity_def:
                self.logger.warning(f"No entity definition found for typeRef: '{type_ref}'")
                continue
            
            # Build fields from entity definition
            fields = []
            
            # Add Properties
            for prop in entity_def.get('Properties', []):
                column_name = prop.get('name', 'Unknown')
                value_type = prop.get('valueType', 'String')
                kusto_type = self._get_kusto_data_type(value_type)
                fields.append(f"{column_name}:{kusto_type}")
            
            # Add TimeseriesProperties
            for ts_prop in entity_def.get('TimeseriesProperties', []):
                column_name = ts_prop.get('name', 'Unknown')
                value_type = ts_prop.get('valueType', 'String')
                kusto_type = self._get_kusto_data_type(value_type)
                fields.append(f"{column_name}:{kusto_type}")
            
            # Add Identifier and Timestamp only if not already present
            # Check if Identifier is already in the fields
            has_identifier = any('Identifier:' in field for field in fields)
            has_timestamp = any('Timestamp:' in field for field in fields)
                
            if not has_identifier:
                fields.append(DEFAULT_IDENTIFIER_FIELD)
            if not has_timestamp:
                fields.append(DEFAULT_TIMESTAMP_FIELD)
            
            entity_mappings.append({
                "entityType": table_name,
                "typeRef": type_ref,
                "displayName": table_name,
                "fields": fields
            })
        
        return entity_mappings
    
    def setup_tables_from_input(self, type_mappings: Optional[List[str]] = None, yaml_file: Optional[str] = None) -> bool:
        """Setup tables based on command line arguments or YAML file input."""
        self.logger.info("🚀 Starting table setup from input...")
        
        # Authenticate first
        if not self.authenticate():
            return False
        
        # Load EntityTypeDefinitions.json
        json_file_path = os.path.join(os.path.dirname(__file__), 'EntityTypeDefinitions.json')
        entity_definitions = self._load_entity_type_definitions(json_file_path)
        
        if not entity_definitions:
            self.logger.error("Failed to load entity type definitions")
            return False
        
        # Get type mappings from input
        mappings = {}
        if yaml_file:
            mappings = self._load_yaml_mappings(yaml_file)
        elif type_mappings:
            mappings = self._parse_type_mappings(type_mappings)
        else:
            self.logger.error("No input provided. Please specify either --type-mappings or --yaml-file")
            return False
        
        if not mappings:
            self.logger.error("No valid type mappings found in input")
            return False
        
        # Step 1: Create AIORawData table first (required for MoveDataByType function)
        self.logger.info(f"Creating {AIO_RAW_DATA_TABLE} table first...")
        aio_table_created = self.create_table(AIO_RAW_DATA_TABLE, AIO_RAW_DATA_SCHEMA)
        if not aio_table_created:
            self.logger.error(f"Failed to create {AIO_RAW_DATA_TABLE} table. Cannot proceed.")
            return False
        
        # Step 2: Create MoveDataByType function (now that AIORawData exists)
        function_created = self.create_kusto_function()
        if not function_created:
            self.logger.error("Failed to create MoveDataByType function. Continuing with table creation...")
        
        # Step 3: Create entity mappings and process remaining tables
        entity_mappings = self._create_entity_mappings_from_input(mappings, entity_definitions)
        results = self.process_entity_mappings(entity_mappings)
        
        # Combine results with AIORawData result
        aio_result = {"AIORawData": aio_table_created}
        all_results = {**aio_result, **results}
        success_count = sum(1 for success in all_results.values() if success)
        total_count = len(all_results)
        
        # Include function creation in overall success assessment
        if function_created:
            self.logger.info("✅ MoveDataByType function created successfully.")
            self.logger.info(f"✅ Script execution completed. {success_count}/{total_count} tables processed successfully.")
            return success_count == total_count
        else:
            self.logger.warning("⚠️ MoveDataByType function creation failed.")
            self.logger.info(f"✅ Script execution completed. {success_count}/{total_count} tables processed successfully.")
            return False  # Overall failure if function creation failed
