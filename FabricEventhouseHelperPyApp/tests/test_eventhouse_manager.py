#!/usr/bin/env python3

import unittest
from unittest.mock import Mock, patch, mock_open
import yaml
import os
import tempfile
from digitaloperations.fabriceventhousehelperpyapp.eventhouse import EventhouseManager
from azure.kusto.data.exceptions import KustoServiceError


class TestEventhouseManager(unittest.TestCase):
    """Test cases for EventhouseManager class"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.cluster_url = "https://test-cluster.kusto.windows.net"
        self.database = "test_database"
        self.manager = EventhouseManager(self.cluster_url, self.database)
        
    def test_init_without_log_file(self):
        """Test EventhouseManager initialization without log file"""
        manager = EventhouseManager(self.cluster_url, self.database)
        self.assertEqual(manager.cluster_url, self.cluster_url)
        self.assertEqual(manager.database, self.database)
        self.assertIsNone(manager.client)
        
    def test_init_with_log_file(self):
        """Test EventhouseManager initialization with log file"""
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            log_file = temp_file.name
        try:
            manager = EventhouseManager(self.cluster_url, self.database, log_file)
            self.assertEqual(manager.cluster_url, self.cluster_url)
            self.assertEqual(manager.database, self.database)
            self.assertIsNone(manager.client)
            # Close the log file handler before cleanup
            manager.close_log_file()
        finally:
            os.unlink(log_file)
    
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_success_azure_cli(self, mock_kcsb, mock_kusto_client):
        """Test successful authentication with Azure CLI"""
        mock_kcsb.with_az_cli_authentication.return_value = Mock()
        mock_client = Mock()
        mock_kusto_client.return_value = mock_client
        
        result = self.manager.authenticate()
        
        self.assertTrue(result)
        self.assertEqual(self.manager.client, mock_client)
        mock_kcsb.with_az_cli_authentication.assert_called_once_with(self.cluster_url)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_fallback_to_device_code(self, mock_kcsb, mock_kusto_client):
        """Test authentication fallback to device code when Azure CLI fails"""
        # Azure CLI fails
        mock_kcsb.with_az_cli_authentication.side_effect = Exception("Azure CLI failed")
        # Device code succeeds
        mock_kcsb.with_aad_device_authentication.return_value = Mock()
        mock_client = Mock()
        mock_kusto_client.return_value = mock_client
        
        result = self.manager.authenticate()
        
        self.assertTrue(result)
        self.assertEqual(self.manager.client, mock_client)
        mock_kcsb.with_az_cli_authentication.assert_called_once_with(self.cluster_url)
        mock_kcsb.with_aad_device_authentication.assert_called_once_with(self.cluster_url)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_all_methods_fail(self, mock_kcsb, mock_kusto_client):
        """Test authentication when all methods fail"""
        mock_kcsb.with_az_cli_authentication.side_effect = Exception("Azure CLI failed")
        mock_kcsb.with_aad_device_authentication.side_effect = Exception("Device code failed")
        
        result = self.manager.authenticate()
        
        self.assertFalse(result)
        self.assertIsNone(self.manager.client)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_azure_cli_specific_errors(self, mock_kcsb, mock_kusto_client):
        """Test Azure CLI authentication with specific error messages that require az login"""
        # Test various Azure CLI error messages that should trigger guidance
        cli_error_messages = [
            "Please run 'az login' to setup account.",
            "not logged in",
            "No subscription found",
            "Authentication failed",
            "az command not found",
            "CLI not found"
        ]
        
        for error_msg in cli_error_messages:
            with self.subTest(error_msg=error_msg):
                mock_kcsb.with_az_cli_authentication.side_effect = Exception(error_msg)
                mock_kcsb.with_aad_device_authentication.side_effect = Exception("Device code failed")
                
                result = self.manager.authenticate()
                
                self.assertFalse(result)
                self.assertIsNone(self.manager.client)
                
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_azure_cli_expired_token(self, mock_kcsb, mock_kusto_client):
        """Test Azure CLI authentication with expired token"""
        mock_kcsb.with_az_cli_authentication.side_effect = Exception("Token expired")
        mock_kcsb.with_aad_device_authentication.side_effect = Exception("Device code failed")
        
        result = self.manager.authenticate()
        
        self.assertFalse(result)
        self.assertIsNone(self.manager.client)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoClient')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.KustoConnectionStringBuilder')
    def test_authenticate_comprehensive_error_logging(self, mock_kcsb, mock_kusto_client):
        """Test that comprehensive error information is logged when authentication fails"""
        azure_cli_error = Exception("Please run 'az login' to setup account.")
        device_code_error = Exception("Device authentication failed")
        
        mock_kcsb.with_az_cli_authentication.side_effect = azure_cli_error
        mock_kcsb.with_aad_device_authentication.side_effect = device_code_error
        
        with patch.object(self.manager.logger, 'error') as mock_error_log:
            result = self.manager.authenticate()
            
            self.assertFalse(result)
            # Verify that error logging was called with appropriate messages
            self.assertTrue(mock_error_log.called)
            # Check that Azure CLI specific guidance was logged
            error_calls = [call.args[0] for call in mock_error_log.call_args_list]
            azure_cli_guidance_logged = any("az login" in msg for msg in error_calls)
            self.assertTrue(azure_cli_guidance_logged)
        
    def test_create_table_without_authentication(self):
        """Test create_table when not authenticated"""
        result = self.manager.create_table("test_table", "col1:string, col2:int")
        self.assertFalse(result)
        
    def test_create_table_success(self):
        """Test successful table creation"""
        mock_client = Mock()
        self.manager.client = mock_client
        mock_client.execute_mgmt.return_value = Mock()
        
        result = self.manager.create_table("test_table", "col1:string, col2:int")
        
        self.assertTrue(result)
        expected_cmd = ".create table test_table (col1:string, col2:int)"
        mock_client.execute_mgmt.assert_called_once_with(self.database, expected_cmd)
        
    def test_create_table_kusto_service_error(self):
        """Test table creation with KustoServiceError"""
        mock_client = Mock()
        self.manager.client = mock_client
        mock_client.execute_mgmt.side_effect = KustoServiceError("Table already exists")
        
        result = self.manager.create_table("test_table", "col1:string, col2:int")
        
        self.assertFalse(result)
        
    def test_set_update_policy_without_authentication(self):
        """Test set_update_policy when not authenticated"""
        result = self.manager.set_update_policy("test_table", "test_type_ref")
        self.assertFalse(result)
        
    def test_set_update_policy_success(self):
        """Test successful update policy setting"""
        mock_client = Mock()
        self.manager.client = mock_client
        mock_client.execute_mgmt.return_value = Mock()
        
        result = self.manager.set_update_policy("test_table", "test_type_ref")
        
        self.assertTrue(result)
        expected_cmd = '.alter table test_table policy update @\'[{"IsEnabled":true,"Source":"AIORawData","Query":"MoveDataByType(\\"test_type_ref\\", \\"test_table\\")","IsTransactional":false}]\''
        mock_client.execute_mgmt.assert_called_once_with(self.database, expected_cmd)
        
    def test_create_kusto_function_without_authentication(self):
        """Test create_kusto_function when not authenticated"""
        result = self.manager.create_kusto_function()
        self.assertFalse(result)
        
    def test_create_kusto_function_success(self):
        """Test successful Kusto function creation"""
        mock_client = Mock()
        self.manager.client = mock_client
        mock_client.execute_mgmt.return_value = Mock()
        
        result = self.manager.create_kusto_function()
        
        self.assertTrue(result)
        mock_client.execute_mgmt.assert_called_once()
        # Check that the function definition was passed
        call_args = mock_client.execute_mgmt.call_args[0]
        self.assertEqual(call_args[0], self.database)
        self.assertIn("MoveDataByType", call_args[1])
        
    def test_get_kusto_data_type(self):
        """Test Kusto data type mapping"""
        self.assertEqual(self.manager._get_kusto_data_type("Number"), "double")
        self.assertEqual(self.manager._get_kusto_data_type("Boolean"), "boolean")
        self.assertEqual(self.manager._get_kusto_data_type("String"), "string")
        self.assertEqual(self.manager._get_kusto_data_type("Object"), "dynamic")
        self.assertEqual(self.manager._get_kusto_data_type("DateTime"), "datetime")
        self.assertEqual(self.manager._get_kusto_data_type("Unknown"), "string")  # Default
        
    @patch('builtins.open', new_callable=mock_open, read_data='[{"Name": "TestEntity", "Namespace": "Test"}]')
    def test_load_entity_type_definitions_success(self, mock_file):
        """Test successful loading of entity type definitions"""
        result = self.manager._load_entity_type_definitions("test.json")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["Name"], "TestEntity")
        
    @patch('builtins.open', side_effect=FileNotFoundError())
    def test_load_entity_type_definitions_file_not_found(self, mock_file):
        """Test loading entity type definitions when file not found"""
        result = self.manager._load_entity_type_definitions("nonexistent.json")
        self.assertEqual(result, [])
        
    @patch('builtins.open', new_callable=mock_open, read_data='invalid json')
    def test_load_entity_type_definitions_invalid_json(self, mock_file):
        """Test loading entity type definitions with invalid JSON"""
        result = self.manager._load_entity_type_definitions("invalid.json")
        self.assertEqual(result, [])
        
    def test_parse_type_mappings_valid_json(self):
        """Test parsing valid JSON type mappings"""
        mappings = [
            '{"typeRef": "test_ref", "namespace": "Test", "entity_name": "Entity"}',
            '{"typeRef": "test_ref2", "namespace": "Test2", "entity_name": "Entity2"}'
        ]
        result = self.manager._parse_type_mappings(mappings)
        
        self.assertEqual(len(result), 2)
        self.assertIn("test_ref", result)
        self.assertEqual(result["test_ref"]["namespace"], "Test")
        self.assertEqual(result["test_ref"]["entity_name"], "Entity")
        
    def test_parse_type_mappings_invalid_json(self):
        """Test parsing invalid JSON type mappings"""
        mappings = ['invalid json', 'not a json object']
        result = self.manager._parse_type_mappings(mappings)
        self.assertEqual(result, {})
        
    def test_parse_type_mappings_missing_fields(self):
        """Test parsing type mappings with missing required fields"""
        mappings = [
            '{"typeRef": "test_ref"}',  # Missing namespace and entity_name
            '{"namespace": "Test", "entity_name": "Entity"}'  # Missing typeRef
        ]
        result = self.manager._parse_type_mappings(mappings)
        self.assertEqual(result, {})
        
    @patch('builtins.open', new_callable=mock_open)
    def test_load_yaml_mappings_success(self, mock_file):
        """Test successful loading of YAML mappings"""
        yaml_content = {
            'type_mappings': [
                {'typeRef': 'test_ref', 'namespace': 'Test', 'entity_name': 'Entity'}
            ]
        }
        mock_file.return_value.read.return_value = yaml.dump(yaml_content)
        
        with patch('yaml.safe_load', return_value=yaml_content):
            result = self.manager._load_yaml_mappings("test.yaml")
            
        self.assertEqual(len(result), 1)
        self.assertIn("test_ref", result)
        
    @patch('builtins.open', side_effect=FileNotFoundError())
    def test_load_yaml_mappings_file_not_found(self, mock_file):
        """Test loading YAML mappings when file not found"""
        result = self.manager._load_yaml_mappings("nonexistent.yaml")
        self.assertEqual(result, {})
        
    def test_create_entity_mappings_from_input(self):
        """Test creating entity mappings from input"""
        type_mappings = {
            "test_ref": {"namespace": "Test", "entity_name": "Entity"}
        }
        entity_definitions = [{
            "Namespace": "Test",
            "Name": "Entity",
            "Properties": [{"name": "prop1", "valueType": "String"}],
            "TimeseriesProperties": [{"name": "ts_prop1", "valueType": "Number"}]
        }]
        
        result = self.manager._create_entity_mappings_from_input(type_mappings, entity_definitions)
        
        self.assertEqual(len(result), 1)
        mapping = result[0]
        self.assertEqual(mapping["displayName"], "Test_Entity")
        self.assertEqual(mapping["typeRef"], "test_ref")
        self.assertIn("prop1:string", mapping["fields"])
        self.assertIn("ts_prop1:double", mapping["fields"])
        self.assertIn("Identifier:string", mapping["fields"])
        self.assertIn("Timestamp:datetime", mapping["fields"])
        
    def test_create_entity_mappings_no_matching_definition(self):
        """Test creating entity mappings when no matching definition found"""
        type_mappings = {
            "test_ref": {"namespace": "NonExistent", "entity_name": "Entity"}
        }
        entity_definitions = [{
            "Namespace": "Test",
            "Name": "Entity",
            "Properties": []
        }]
        
        result = self.manager._create_entity_mappings_from_input(type_mappings, entity_definitions)
        
        self.assertEqual(len(result), 0)
        
    def test_process_entity_mappings_success(self):
        """Test successful processing of entity mappings"""
        mock_client = Mock()
        self.manager.client = mock_client
        mock_client.execute_mgmt.return_value = Mock()
        
        entity_mappings = [{
            "displayName": "test_table",
            "typeRef": "test_ref",
            "fields": ["col1:string", "col2:int"]
        }]
        
        result = self.manager.process_entity_mappings(entity_mappings)
        
        self.assertEqual(len(result), 1)
        self.assertTrue(result["test_table"])
        # Should call create table and set update policy
        self.assertEqual(mock_client.execute_mgmt.call_count, 2)
        
    def test_process_entity_mappings_table_creation_fails(self):
        """Test processing entity mappings when table creation fails"""
        mock_client = Mock()
        self.manager.client = mock_client
        # First call (create table) fails, second call shouldn't happen
        mock_client.execute_mgmt.side_effect = [KustoServiceError("Failed")]
        
        entity_mappings = [{
            "displayName": "test_table",
            "typeRef": "test_ref",
            "fields": ["col1:string", "col2:int"]
        }]
        
        result = self.manager.process_entity_mappings(entity_mappings)
        
        self.assertEqual(len(result), 1)
        self.assertFalse(result["test_table"])
        # Only create table should be called, not update policy
        self.assertEqual(mock_client.execute_mgmt.call_count, 1)


class TestEventhouseManagerIntegration(unittest.TestCase):
    """Integration tests for EventhouseManager"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.cluster_url = "https://test-cluster.kusto.windows.net"
        self.database = "test_database"
        self.manager = EventhouseManager(self.cluster_url, self.database)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.authenticate')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._load_entity_type_definitions')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._load_yaml_mappings')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.create_table')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.create_kusto_function')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.process_entity_mappings')
    def test_setup_tables_from_input_yaml_success(
        self, mock_process, mock_function, mock_create_table,
        mock_load_yaml, mock_load_entities, mock_auth
    ):
        """Test successful setup from YAML input"""
        mock_auth.return_value = True
        mock_load_entities.return_value = [{"Namespace": "Test", "Name": "Entity", "Properties": []}]
        mock_load_yaml.return_value = {"test_ref": {"namespace": "Test", "entity_name": "Entity"}}
        mock_create_table.return_value = True
        mock_function.return_value = True
        mock_process.return_value = {"Test_Entity": True}
        
        result = self.manager.setup_tables_from_input(yaml_file="test.yaml")
        
        self.assertTrue(result)
        mock_auth.assert_called_once()
        mock_load_entities.assert_called_once()
        mock_load_yaml.assert_called_once_with("test.yaml")
        mock_create_table.assert_called_once()  # AIORawData table
        mock_function.assert_called_once()
        mock_process.assert_called_once()
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.authenticate')
    def test_setup_tables_from_input_authentication_fails(self, mock_auth):
        """Test setup when authentication fails"""
        mock_auth.return_value = False
        
        result = self.manager.setup_tables_from_input(yaml_file="test.yaml")
        
        self.assertFalse(result)
        mock_auth.assert_called_once()
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.authenticate')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._load_entity_type_definitions')
    def test_setup_tables_from_input_no_entity_definitions(self, mock_load_entities, mock_auth):
        """Test setup when entity definitions cannot be loaded"""
        mock_auth.return_value = True
        mock_load_entities.return_value = []
        
        result = self.manager.setup_tables_from_input(yaml_file="test.yaml")
        
        self.assertFalse(result)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.authenticate')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._load_entity_type_definitions')
    def test_setup_tables_from_input_no_input_provided(self, mock_load_entities, mock_auth):
        """Test setup when no input is provided"""
        mock_auth.return_value = True
        mock_load_entities.return_value = [{"Namespace": "Test", "Name": "Entity"}]
        
        result = self.manager.setup_tables_from_input()
        
        self.assertFalse(result)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.authenticate')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._load_entity_type_definitions')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager._parse_type_mappings')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.create_table')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.create_kusto_function')
    @patch('digitaloperations.fabriceventhousehelperpyapp.eventhouse.EventhouseManager.process_entity_mappings')
    def test_setup_tables_from_input_json_success(
        self, mock_process, mock_function, mock_create_table,
        mock_parse_json, mock_load_entities, mock_auth
    ):
        """Test successful setup from JSON command line input"""
        mock_auth.return_value = True
        mock_load_entities.return_value = [{"Namespace": "Test", "Name": "Entity", "Properties": []}]
        mock_parse_json.return_value = {"test_ref": {"namespace": "Test", "entity_name": "Entity"}}
        mock_create_table.return_value = True
        mock_function.return_value = True
        mock_process.return_value = {"Test_Entity": True}
        
        type_mappings = ['{"typeRef": "test_ref", "namespace": "Test", "entity_name": "Entity"}']
        result = self.manager.setup_tables_from_input(type_mappings=type_mappings)
        
        self.assertTrue(result)
        mock_parse_json.assert_called_once_with(type_mappings)


if __name__ == '__main__':
    unittest.main()
