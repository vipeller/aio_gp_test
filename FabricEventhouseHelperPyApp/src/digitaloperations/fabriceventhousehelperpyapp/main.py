#!/usr/bin/env python3

import argparse
import logging
import sys
from typing import Optional, List

from digitaloperations.fabriceventhousehelperpyapp.eventhouse import EventhouseManager
from azure.kusto.data.exceptions import KustoAuthenticationError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)


def setup_eventhouse(database_name: str, cluster_name: str, log_file: Optional[str],
                     type_mappings: Optional[List[str]] = None, yaml_file: Optional[str] = None,
                     verbose: bool = False) -> bool:
    """Setup the Fabric Eventhouse with tables and functions."""
    logging.info("Setting up Fabric Eventhouse...")
    logging.info(f"Database: {database_name}")
    logging.info(f"Cluster: {cluster_name}")
    logging.info(f"Log file: {log_file}")
    
    # Input validation
    if not database_name or not database_name.strip():
        print("❌ Error: Database name cannot be empty")
        return False
    
    if not cluster_name or not cluster_name.strip():
        print("❌ Error: Cluster name cannot be empty")
        return False
    
    # Create the EventhouseManager and run setup
    manager = None
    try:
        manager = EventhouseManager(cluster_name, database_name, log_file, verbose)
        
        # Require explicit input - no default setup
        if type_mappings or yaml_file:
            print("Using dynamic input for table setup...")
            success = manager.setup_tables_from_input(type_mappings, yaml_file)
        else:
            print("❌ Error: No input provided. Please specify either --type-mappings or --yaml-file")
            return False
        
        if success:
            print("✅ Eventhouse setup completed successfully!")
        else:
            print("❌ Eventhouse setup failed!")
            print("💡 Check the log file for detailed error information.")
        
        return success
    except KeyboardInterrupt:
        print("\n⚠️  Operation cancelled by user.")
        return False
    except KustoAuthenticationError as e:
        logging.error(f"Kusto authentication error: {e}")
        error_msg = str(e).lower()
        
        print("❌ Azure authentication failed!")
        
        # Check for specific Azure CLI token errors
        if any(keyword in error_msg for keyword in [
            "azclitokenprovider", "failed to obtain az cli token", "az login"
        ]):
            print("\n🔧 Azure CLI Authentication Issue:")
            print("   1. Run: az login")
            print("   2. Ensure Azure CLI version 2.3.0+ is installed")
            print("   3. Verify you have access to the Fabric workspace")
            print("   4. Check that your account has the necessary permissions")
        elif "device" in error_msg:
            print("\n🔧 Device Code Authentication Issue:")
            print("   1. Complete the device authentication flow")
            print("   2. Check your browser for authentication prompts")
            print("   3. Verify your account has access to the resource")
        else:
            print("\n🔧 General Authentication Troubleshooting:")
            print("   1. Run: az login")
            print("   2. Verify cluster URL format")
            print("   3. Check your permissions to the Fabric workspace")
        
        print(f"\n📋 Technical details: {e}")
        return False
    except Exception as e:
        error_msg = str(e).lower()
        logging.error(f"Error during setup: {e}")
        
        # Provide specific guidance for authentication errors
        if any(keyword in error_msg for keyword in ["authentication", "login", "credential"]):
            print(f"❌ Authentication failed: {e}")
            print("\n🔧 To fix this:")
            print("   1. Run: az login")
            print("   2. Verify cluster URL format")
            print("   3. Check your permissions to the Fabric workspace")
        else:
            print(f"❌ Setup failed with error: {e}")
            print("💡 Check the log file for detailed error information.")
        
        return False
    finally:
        # Ensure proper cleanup
        if manager:
            manager.close_log_file()


def main():
    try:
        parser = argparse.ArgumentParser(
            description="Fabric Eventhouse Helper - CLI tool for setting up Fabric Eventhouse with tables and policies."
        )
        
        # Create subparsers for different commands
        subparsers = parser.add_subparsers(dest='command', help='Available commands')
        
        # Eventhouse setup command
        eventhouse_parser = subparsers.add_parser('setup-eventhouse', help='Setup Fabric Eventhouse')
        eventhouse_parser.add_argument(
            "--cluster",
            type=str,
            help="Eventhouse Query URI",
            required=True
        )
        eventhouse_parser.add_argument(
            "--database",
            type=str,
            help="Database name",
            required=True
        )
        eventhouse_parser.add_argument(
            "--type-mappings",
            type=str,
            nargs='+',
            help="List of structured mappings in JSON format: '{\"typeRef\":\"...\",\"namespace\":\"...\",\"entity_name\":\"...\"}'",
            default=None
        )
        eventhouse_parser.add_argument(
            "--yaml-file",
            type=str,
            help="Path to YAML file containing type mappings",
            default=None
        )
        eventhouse_parser.add_argument(
            "--log-file",
            type=str,
            help="Log file path (optional)",
            default=None
        )
        eventhouse_parser.add_argument(
            "--verbose",
            action="store_true",
            help="Enable verbose output"
        )
        
        args = parser.parse_args()
        
        # Handle commands
        if args.command == 'setup-eventhouse':
            # Handle verbose logging for setup-eventhouse command
            if hasattr(args, 'verbose') and args.verbose:
                logging.getLogger().setLevel(logging.DEBUG)
            
            success = setup_eventhouse(args.database, args.cluster, args.log_file, args.type_mappings, args.yaml_file, args.verbose)
            if not success:
                logging.error("Eventhouse setup failed.")
                sys.exit(1)
            else:
                logging.info("Eventhouse setup completed successfully.")
                
        else:
            # No command specified, show help
            parser.print_help()
            sys.exit(1)

    except KeyboardInterrupt:
        logging.info("Operation cancelled by user.")
        print("Operation cancelled by user.")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
