#!/usr/bin/env python3

import unittest
from unittest.mock import Mock, patch
from io import StringIO
from digitaloperations.fabriceventhousehelperpyapp.main import setup_eventhouse, main


class TestMainFunctions(unittest.TestCase):
    """Test cases for main.py functions"""
    
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('builtins.print')
    def test_setup_eventhouse_with_yaml_success(self, mock_print, mock_manager_class):
        """Test successful setup with YAML file"""
        mock_manager = Mock()
        mock_manager_class.return_value = mock_manager
        mock_manager.setup_tables_from_input.return_value = True
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertTrue(result)
        mock_manager_class.assert_called_once_with("test_cluster", "test_db", "test.log", False)
        mock_manager.setup_tables_from_input.assert_called_once_with(None, "test.yaml")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('builtins.print')
    def test_setup_eventhouse_with_type_mappings_success(self, mock_print, mock_manager_class):
        """Test successful setup with type mappings"""
        mock_manager = Mock()
        mock_manager_class.return_value = mock_manager
        mock_manager.setup_tables_from_input.return_value = True
        
        type_mappings = ['{"typeRef": "test", "namespace": "Test", "entity_name": "Entity"}']
        result = setup_eventhouse("test_db", "test_cluster", "test.log", type_mappings=type_mappings)
        
        self.assertTrue(result)
        mock_manager.setup_tables_from_input.assert_called_once_with(type_mappings, None)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('builtins.print')
    def test_setup_eventhouse_failure(self, mock_print, mock_manager_class):
        """Test setup failure"""
        mock_manager = Mock()
        mock_manager_class.return_value = mock_manager
        mock_manager.setup_tables_from_input.return_value = False
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertFalse(result)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.logging')
    @patch('builtins.print')
    def test_setup_eventhouse_authentication_error(self, mock_print, mock_logging, mock_manager_class):
        """Test setup with authentication error"""
        mock_manager_class.side_effect = Exception("Authentication failed - please login")
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertFalse(result)
        # Verify that authentication-specific guidance is printed
        mock_print.assert_any_call("❌ Authentication failed: Authentication failed - please login")
        mock_print.assert_any_call("\n🔧 To fix this:")
        mock_print.assert_any_call("   1. Run: az login")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.logging')
    @patch('builtins.print')
    def test_setup_eventhouse_credential_error(self, mock_print, mock_logging, mock_manager_class):
        """Test setup with credential error"""
        mock_manager_class.side_effect = Exception("Invalid credentials provided")
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertFalse(result)
        # Verify that authentication-specific guidance is printed
        mock_print.assert_any_call("❌ Authentication failed: Invalid credentials provided")
        mock_print.assert_any_call("\n🔧 To fix this:")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.logging')
    @patch('builtins.print')
    def test_setup_eventhouse_generic_error(self, mock_print, mock_logging, mock_manager_class):
        """Test setup with generic error (non-authentication)"""
        mock_manager_class.side_effect = Exception("Network timeout error")
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertFalse(result)
        # Verify that generic error message is printed (not authentication guidance)
        mock_print.assert_any_call("❌ Setup failed with error: Network timeout error")
        mock_print.assert_any_call("💡 Check the log file for detailed error information.")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.EventhouseManager')
    @patch('builtins.print')
    def test_setup_eventhouse_keyboard_interrupt(self, mock_print, mock_manager_class):
        """Test setup with keyboard interrupt"""
        mock_manager_class.side_effect = KeyboardInterrupt()
        
        result = setup_eventhouse("test_db", "test_cluster", "test.log", yaml_file="test.yaml")
        
        self.assertFalse(result)
        mock_print.assert_any_call("\n⚠️  Operation cancelled by user.")
        
    @patch('builtins.print')
    def test_setup_eventhouse_no_input(self, mock_print):
        """Test setup with no input provided"""
        result = setup_eventhouse("test_db", "test_cluster", "test.log")
        
        self.assertFalse(result)
        mock_print.assert_any_call("❌ Error: No input provided. Please specify either --type-mappings or --yaml-file")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster',
                        '--database', 'test-db', '--log-file', 'test.log',
                        '--yaml-file', 'test.yaml'])
    def test_main_setup_eventhouse_yaml_success(self, mock_setup):
        """Test main function with setup-eventhouse command and YAML file"""
        mock_setup.return_value = True
        
        # When successful, main() doesn't call sys.exit()
        main()
            
        mock_setup.assert_called_once_with('test-db', 'test-cluster', 'test.log',
                                           None, 'test.yaml', False)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--type-mappings', '{"typeRef": "test", "namespace": "Test", "entity_name": "Entity"}'])
    def test_main_setup_eventhouse_json_success(self, mock_setup):
        """Test main function with setup-eventhouse command and JSON type mappings"""
        mock_setup.return_value = True
        
        # When successful, main() doesn't call sys.exit()
        main()
            
        expected_mappings = ['{"typeRef": "test", "namespace": "Test", "entity_name": "Entity"}']
        mock_setup.assert_called_once_with('test-db', 'test-cluster', 'test.log', 
                                           expected_mappings, None, False)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--yaml-file', 'test.yaml'])
    def test_main_setup_eventhouse_failure(self, mock_setup):
        """Test main function when setup fails"""
        mock_setup.return_value = False
        
        with patch('sys.exit') as mock_exit:
            main()
            
        mock_exit.assert_called_once_with(1)
        
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log'])
    def test_main_setup_eventhouse_no_input_args(self):
        """Test main function with no type mappings or YAML file provided"""
        with patch('sys.exit') as mock_exit:
            with patch('builtins.print'):
                main()
                
        mock_exit.assert_called_once_with(1)
        
    @patch('sys.argv', ['main.py', '--help'])
    def test_main_help(self):
        """Test main function with help argument"""
        with patch('sys.exit') as mock_exit:
            with patch('sys.stdout', new_callable=StringIO):
                try:
                    main()
                except SystemExit:
                    pass
                    
        # Help should exit with code 1 (according to actual behavior)
        mock_exit.assert_called_with(1)
        
    @patch('sys.argv', ['main.py', 'invalid-command'])
    def test_main_invalid_command(self):
        """Test main function with invalid command"""
        with patch('sys.exit') as mock_exit:
            with patch('sys.stderr', new_callable=StringIO):
                try:
                    main()
                except SystemExit:
                    pass
                    
        # Invalid command should exit with error code 1 (according to actual behavior)
        mock_exit.assert_called_with(1)
        
    @patch('sys.argv', ['main.py'])
    def test_main_no_command(self):
        """Test main function with no command provided"""
        with patch('sys.exit') as mock_exit:
            with patch('sys.stderr', new_callable=StringIO):
                try:
                    main()
                except SystemExit:
                    pass
                    
        # No command should exit with error code 1 (according to actual behavior)
        mock_exit.assert_called_with(1)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--type-mappings', 
                        '{"typeRef": "ref1", "namespace": "NS1", "entity_name": "Entity1"}',
                        '{"typeRef": "ref2", "namespace": "NS2", "entity_name": "Entity2"}'])
    def test_main_multiple_type_mappings(self, mock_setup):
        """Test main function with multiple type mappings"""
        mock_setup.return_value = True
        
        # When successful, main() doesn't call sys.exit()
        main()
            
        expected_mappings = [
            '{"typeRef": "ref1", "namespace": "NS1", "entity_name": "Entity1"}',
            '{"typeRef": "ref2", "namespace": "NS2", "entity_name": "Entity2"}'
        ]
        mock_setup.assert_called_once_with('test-db', 'test-cluster', 'test.log',
                                           expected_mappings, None, False)
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--yaml-file', 'test.yaml', '--type-mappings', 
                        '{"typeRef": "test", "namespace": "Test", "entity_name": "Entity"}'])
    def test_main_both_yaml_and_type_mappings(self, mock_setup):
        """Test main function with both YAML file and type mappings provided"""
        mock_setup.return_value = True
        
        # When successful, main() doesn't call sys.exit()
        main()
            
        # Both should be passed to setup function
        expected_mappings = ['{"typeRef": "test", "namespace": "Test", "entity_name": "Entity"}']
        mock_setup.assert_called_once_with('test-db', 'test-cluster', 'test.log',
                                           expected_mappings, 'test.yaml', False)


class TestMainExceptionHandling(unittest.TestCase):
    """Test exception handling in main function"""
    
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--yaml-file', 'test.yaml'])
    def test_main_with_exception(self, mock_setup):
        """Test main function when an exception occurs"""
        mock_setup.side_effect = Exception("Test exception")
        
        with patch('sys.exit') as mock_exit:
            mock_exit.return_value = None
            main()
            # Assert that sys.exit was called to avoid unused variable error
            self.assertTrue(mock_exit.called)
            mock_exit.assert_called_once_with(1)
        # The error is logged, not printed
        # mock_print.assert_any_call("An error occurred: Test exception")
        
    @patch('digitaloperations.fabriceventhousehelperpyapp.main.setup_eventhouse')
    @patch('sys.argv', ['main.py', 'setup-eventhouse', '--cluster', 'test-cluster', 
                        '--database', 'test-db', '--log-file', 'test.log', 
                        '--yaml-file', 'test.yaml'])
    def test_main_with_keyboard_interrupt(self, mock_setup):
        """Test main function when KeyboardInterrupt occurs"""
        mock_setup.side_effect = KeyboardInterrupt()
        with patch('sys.exit') as mock_exit:
            mock_exit.return_value = None
            with patch('builtins.print') as mock_print:
                main()
                
        mock_exit.assert_called_once_with(1)
        mock_print.assert_any_call("Operation cancelled by user.")


if __name__ == '__main__':
    unittest.main()
