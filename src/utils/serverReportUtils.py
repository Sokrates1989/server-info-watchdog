## Utilities for report or info message creation.

# For getting current timestamp.
import time
# For file operations with operating system.
import os
# To improve error indication (sys.exit).
import sys
# For getting config.
import json
# To create enumerations.
from enum import Enum

## Own classes.
from serverReport import ServerReport
import timeStringUtils
from watchdogConfig import get_config, Thresholds

class MessagingPlatform(Enum):
    DEFAULT = "Default"
    EMAIL = "Email"
    TELEGRAM = "Telegram"


class ThresholdStatus(Enum):
    OK = "OK"
    WARNING = "WARNING"
    ERROR = "ERROR"

    
class ServerReportUtils:
    def __init__(self):

        # Load config from environment/watchdog.env.
        self._config = get_config()

        # ServerName.
        self.server_name = self._config.server_name

        # Gluster install settings.
        self.gluster_not_installed_handling = self._config.gluster_not_installed_handling
        if not self.gluster_not_installed_handling:
            self.gluster_not_installed_handling = "not specified"

        
        # Server info file.
        try:
            server_info_file_path_and_name = os.path.join(os.path.dirname(__file__), "..", "..", "serverInfo/", "system_info.json")
            with open(server_info_file_path_and_name) as server_info_file:
                self.server_info_array = json.load(server_info_file)
        except Exception as e:
            errorMessage = "There has been an error creating a report for " + self.server_name + ":\n"
            errorMessage += f"\nCould not read serverInfo/system_info.json: {e} \nDid you map the serverInfo directory correctly? \nHas the report been created on the server? \n"
            raise Exception(errorMessage)

        

    # Create a simple consize text message from the server state json and server state.
    def getServerReport(self, messagePlatform: MessagingPlatform = MessagingPlatform.DEFAULT) -> ServerReport:

        # Save, if there have been warnings or errors.
        hasWarning=False
        hasError=False

        # Icons to emphasize warning or error state.
        errorIcon="🚨"
        warningIcon="⚠️"
        
        # Helper function to format text as code.
        def wrap_with_code(text):
            return f"<code>{text}</code>"
        
        # Helper function to format text as bold.
        def italicUnderline(text):
            return f"<u><i>{text}</i></u>"
        
        # Determine, if array is empty (or only contains one empty string).
        def isArrayEmpty(array):
            if array:
                if len(array) == 1:
                    if array[0]:
                        return False
                    else:
                        return True
                else:
                    return False
            else:
                return True

        # Initialize the serverReport.
        serverReport = ""

        # Hostname.
        serverReport += f"<b>Hostname:</b> {wrap_with_code(self.server_info_array['system_info']['hostname'])}\n"

        # Timestamp.
        current_timestamp = int(time.time())
        system_info_timestamp = self.server_info_array['timestamp']['unix_format']
        thresholds = self.get_thresholds('timestampAgeMinutes')
        stateIndicatingIcon = ""
        if int(current_timestamp) > int(system_info_timestamp) + float(thresholds.error) * 60:
            hasError = True
            stateIndicatingIcon = errorIcon
        elif int(current_timestamp) > int(system_info_timestamp) + float(thresholds.warning) * 60:
            hasWarning = True
            stateIndicatingIcon = warningIcon
        serverReport += stateIndicatingIcon + f"<b>Timestamp:</b> {wrap_with_code(self.server_info_array['timestamp']['human_readable_format'])}\n"

        # Add Last 15min CPU Percentage.
        thresholds = self.get_thresholds('cpu')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['cpu']['last_15min_cpu_percentage'].strip().strip("%"))
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        cpu_percentage_string=self.server_info_array['cpu']['last_15min_cpu_percentage'] + "%"
        serverReport += stateIndicatingIcon + f"<b>CPU:</b> {wrap_with_code(cpu_percentage_string)}\n"

        # Add Disk Usage information.
        thresholds = self.get_thresholds('disk')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['disk']['disk_usage_percentage'].strip().strip("%"))
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        disk_usage_info = f"{self.server_info_array['disk']['disk_usage_percentage']} " \
                        f"({self.server_info_array['disk']['disk_usage_amount']} / {self.server_info_array['disk']['total_disk_avail']})"
        serverReport += stateIndicatingIcon + f"<b>Disk:</b> {wrap_with_code(disk_usage_info)}\n"

        # Add Memory Usage information.
        thresholds = self.get_thresholds('memory')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['memory']['memory_usage_percentage'].strip().strip("%"))
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        memory_usage_info = f"{self.server_info_array['memory']['memory_usage_percentage']}% " \
                            f"({self.server_info_array['memory']['used_memory_human']} / {self.server_info_array['memory']['total_memory_human']})"
        serverReport += stateIndicatingIcon + f"<b>Memory:</b> {wrap_with_code(memory_usage_info)}\n"

        # Add Swap Status information.
        stateIndicatingIcon = ""
        if self.server_info_array['swap']['swap_status'] != "Off":
            hasWarning = True
            stateIndicatingIcon = warningIcon
        serverReport += stateIndicatingIcon + f"<b>Swap Status:</b> {wrap_with_code(self.server_info_array['swap']['swap_status'])}\n"
        
        # Add Processes.
        thresholds = self.get_thresholds('processes')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['processes']['amount_processes'])
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        serverReport += stateIndicatingIcon + f"<b>Processes:</b> {wrap_with_code(self.server_info_array['processes']['amount_processes'])}\n"
        
        # Users information.
        thresholds = self.get_thresholds('users')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['users']['logged_in_users'])
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        serverReport += stateIndicatingIcon + f"<b>Logged In Users:</b> {wrap_with_code(self.server_info_array['users']['logged_in_users'])}\n"

        # Network info in server info?
        if 'network' in self.server_info_array:

            # Vnstab Enabled?
            if self.server_info_array['network']['is_vnstab_installed'].upper() == "TRUE":

                # Enough network data?
                if self.server_info_array['network']['has_vnstab_enough_data'].upper() == "TRUE":

                    # Thresholds in config?
                    thresholds_available = True
                    try:
                        thresholds_up = self.get_thresholds('network_up')
                        thresholds_down = self.get_thresholds('network_down')
                        thresholds_total = self.get_thresholds('network_total')
                    except Exception as e:
                        thresholds_available = False


                    # Add Network Usage information.
                    if thresholds_available == True:

                        # Network up.
                        thresholds = thresholds_up
                        stateIndicatingIcon = ""
                        system_value = float(self.server_info_array['network']['upstream_avg_bits'].strip())
                        if system_value > float(thresholds.error) and float(thresholds.error) != 0:
                            hasError = True
                            stateIndicatingIcon = errorIcon
                        elif system_value > float(thresholds.warning) and float(thresholds.warning) != 0:
                            hasWarning = True
                            stateIndicatingIcon = warningIcon
                        network_up_info = f"{self.server_info_array['network']['upstream_avg_human']}"
                        serverReport += stateIndicatingIcon + f"<b>Network Upstream:</b> {wrap_with_code(network_up_info)}\n"

                        # Network down.
                        thresholds = thresholds_down
                        stateIndicatingIcon = ""
                        system_value = float(self.server_info_array['network']['downstream_avg_bits'].strip())
                        if system_value > float(thresholds.error) and float(thresholds.error) != 0:
                            hasError = True
                            stateIndicatingIcon = errorIcon
                        elif system_value > float(thresholds.warning) and float(thresholds.warning) != 0:
                            hasWarning = True
                            stateIndicatingIcon = warningIcon
                        network_up_info = f"{self.server_info_array['network']['downstream_avg_human']}"
                        serverReport += stateIndicatingIcon + f"<b>Network Downstream:</b> {wrap_with_code(network_up_info)}\n"

                        # Network total.
                        thresholds = thresholds_total
                        stateIndicatingIcon = ""
                        system_value = float(self.server_info_array['network']['total_network_avg_bits'].strip())
                        if system_value > float(thresholds.error) and float(thresholds.error) != 0:
                            hasError = True
                            stateIndicatingIcon = errorIcon
                        elif system_value > float(thresholds.warning) and float(thresholds.warning) != 0:
                            hasWarning = True
                            stateIndicatingIcon = warningIcon
                        network_up_info = f"{self.server_info_array['network']['total_network_avg_human']}"
                        serverReport += stateIndicatingIcon + f"<b>Network Total:</b> {wrap_with_code(network_up_info)}\n"

                    else:
                        # No Thresholds in config.
                        hasError = True
                        stateIndicatingIcon = errorIcon
                        network_error_msg = f"No network thresholds in config"
                        serverReport += stateIndicatingIcon + f"<b>Network:</b> {wrap_with_code(network_error_msg)}\n"
                else:
                    # Not Enough vnstab data yet.
                    hasWarning = True
                    stateIndicatingIcon = warningIcon
                    network_error_msg = f"Vnstab does not have enough data yet"
                    serverReport += stateIndicatingIcon + f"<b>Network:</b> {wrap_with_code(network_error_msg)}\n"
            else:
                # Vnstab is not enabled.
                hasError = True
                stateIndicatingIcon = errorIcon
                network_error_msg = f"Vnstab is not enabled"
                serverReport += stateIndicatingIcon + f"<b>Network:</b> {wrap_with_code(network_error_msg)}\n" 
        else:
            # No Network info in server info.
            hasError = True
            stateIndicatingIcon = errorIcon
            network_error_msg = f"No network info in server info array"
            serverReport += stateIndicatingIcon + f"<b>Network:</b> {wrap_with_code(network_error_msg)}\n"

        
        # Gluster info in server_info_array?
        if 'gluster' in self.server_info_array:

            # Gluster installed?
            if self.server_info_array['gluster']['is_gluster_installed'].upper() == "TRUE":

                # Any unhealthy peers?
                number_of_peers = int(self.server_info_array['gluster']['number_of_peers'])
                number_of_healthy_peers = int(self.server_info_array['gluster']['number_of_healthy_peers'])
                number_of_unhealthy_peers = number_of_peers - number_of_healthy_peers

                # Gluster peers Message.
                gluster_peers_msg = wrap_with_code(f"Gluster Peers (Healthy: {number_of_healthy_peers} / Total: {number_of_peers})\n")

                # Add peers output, if there are any unhealthy peers.
                if number_of_unhealthy_peers != 0:
                    for peer in self.server_info_array['gluster']['gluster_peers']:
                        gluster_peers_msg += wrap_with_code(peer) + "\n"


                # Any unhealthy volumes?
                number_of_volumes = int(self.server_info_array['gluster']['number_of_volumes'])
                number_of_healthy_volumes = int(self.server_info_array['gluster']['number_of_healthy_volumes'])
                number_of_unhealthy_volumes = number_of_volumes - number_of_healthy_volumes

                # Gluster volumes Message.
                gluster_volumes_msg = wrap_with_code(f"Gluster Volumes (Healthy: {number_of_healthy_volumes} / Total: {number_of_volumes})\n")

                # Add volumes output, if there are any unhealthy volumes.
                if number_of_unhealthy_volumes != 0:
                    for index, volume in enumerate(self.server_info_array['gluster']['gluster_volumes']):
                        gluster_volumes_msg += italicUnderline("Volume: ") + wrap_with_code(volume) + "\n"

                        # Print unhealthy bricks, if there are any.
                        if self.server_info_array['gluster']['all_unhealthy_bricks'][index]:
                            if not isArrayEmpty(self.server_info_array['gluster']['all_unhealthy_bricks'][index]):
                                gluster_volumes_msg += italicUnderline("Unhealthy Bricks: ")
                                for item in self.server_info_array['gluster']['all_unhealthy_bricks'][index]:
                                    gluster_volumes_msg += wrap_with_code(item) + ", "
                                # Remove the last occurrence of ", " and add a newline character.
                                gluster_volumes_msg = gluster_volumes_msg.rstrip(", ") + "\n"

                        # Print unhealthy processes, if there are any.
                        if self.server_info_array['gluster']['all_unhealthy_processes'][index]:
                            if not isArrayEmpty(self.server_info_array['gluster']['all_unhealthy_processes'][index]):
                                gluster_volumes_msg += italicUnderline("Unhealthy Processes: ")
                                for item in self.server_info_array['gluster']['all_unhealthy_processes'][index]:
                                    gluster_volumes_msg += wrap_with_code(item) + ", "
                                # Remove the last occurrence of ", " and add a newline character.
                                gluster_volumes_msg = gluster_volumes_msg.rstrip(", ") + "\n"

                        # Print errors/warnings, if there are any.
                        if self.server_info_array['gluster']['all_errors_warnings'][index]:
                            if not isArrayEmpty(self.server_info_array['gluster']['all_errors_warnings'][index]):
                                gluster_volumes_msg += italicUnderline("Errors/Warnings: ")
                                for item in self.server_info_array['gluster']['all_errors_warnings'][index]:
                                    if item:
                                        gluster_volumes_msg += wrap_with_code(item) + ", "
                                # Remove the last occurrence of ", " and add a newline character.
                                gluster_volumes_msg = gluster_volumes_msg.rstrip(", ") + "\n"

                        # Print active tasks, if there are any.
                        if self.server_info_array['gluster']['all_active_tasks'][index]:
                            if not isArrayEmpty(self.server_info_array['gluster']['all_active_tasks'][index]):
                                gluster_volumes_msg += italicUnderline("Active Tasks: ")
                                for item in self.server_info_array['gluster']['all_active_tasks'][index]:
                                    gluster_volumes_msg += wrap_with_code(item) + ", "
                                # Remove the last occurrence of ", " and add a newline character.
                                gluster_volumes_msg = gluster_volumes_msg.rstrip(", ") + "\n"



                # Thresholds in config?
                thresholds_available = True
                try:
                    gluster_unhealthy_peers = self.get_thresholds('gluster_unhealthy_peers')
                    gluster_unhealthy_volumes = self.get_thresholds('gluster_unhealthy_volumes')
                except Exception as e:
                    thresholds_available = False

                # Add Network Usage information.
                if thresholds_available == True:

                    # Unhealthy peers.
                    thresholds = gluster_unhealthy_peers
                    stateIndicatingIcon = ""
                    system_value = number_of_unhealthy_peers
                    if system_value >= float(thresholds.error) and float(thresholds.error) != 0:
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning) and float(thresholds.warning) != 0:
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                    serverReport += stateIndicatingIcon + f"<b>Gluster Peers:</b> {gluster_peers_msg}"

                    # Unhealthy volumes.
                    thresholds = gluster_unhealthy_volumes
                    stateIndicatingIcon = ""
                    system_value = number_of_unhealthy_volumes
                    if system_value >= float(thresholds.error) and float(thresholds.error) != 0:
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning) and float(thresholds.warning) != 0:
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                    serverReport += stateIndicatingIcon + f"<b>Gluster Volumes:</b> {gluster_volumes_msg}"

                else:
                    # No Thresholds in config.
                    hasError = True
                    stateIndicatingIcon = errorIcon
                    gluster_error_msg = f"No gluster thresholds in config"
                    serverReport += stateIndicatingIcon + f"<b>Gluster:</b> {wrap_with_code(gluster_error_msg)}\n"

            else:
                # Gluster is not installed -> Determine handling.

                # Prepare message and icon.
                gluster_error_msg = "Gluster is not installed. "
                stateIndicatingIcon = ""

                # Check the config value and handle 
                if self.gluster_not_installed_handling.upper() == "WARNING":
                    stateIndicatingIcon = warningIcon
                    hasWarning = True

                elif self.gluster_not_installed_handling.upper() == "ERROR":
                    stateIndicatingIcon = errorIcon
                    hasError = True

                elif self.gluster_not_installed_handling.upper() == "NONE":
                    gluster_error_msg += ""

                elif self.gluster_not_installed_handling == "not specified":
                    gluster_error_msg += "Unspecified config value. Please specify 'warning', 'error', or 'none' for gluster_not_installed_handling."
                    stateIndicatingIcon = errorIcon
                    hasError = True

                else:
                    gluster_error_msg += "Invalid config value. Please specify 'warning', 'error', or 'none' for gluster_not_installed_handling."
                    stateIndicatingIcon = errorIcon
                    hasError = True

                serverReport += stateIndicatingIcon + f"<b>Gluster:</b> {wrap_with_code(gluster_error_msg)}\n" 
        else:
            # No Gluster info in server info.
            hasError = True
            stateIndicatingIcon = errorIcon
            gluster_error_msg = f"No gluster info in server info array"
            serverReport += stateIndicatingIcon + f"<b>Gluster:</b> {wrap_with_code(gluster_error_msg)}\n"


        # Add Updates information.
        thresholds = self.get_thresholds('updates')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['updates']['amount_of_available_updates'])
        if system_value > float(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > float(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        updates_info = f"{self.server_info_array['updates']['amount_of_available_updates']} " \
                    f"({self.server_info_array['updates']['updates_available_output']})"
        serverReport += stateIndicatingIcon + f"<b>Available Updates:</b> {wrap_with_code(updates_info)}\n"

        # Add Kernel information (if available in JSON).
        if 'kernel' in self.server_info_array:
            stateIndicatingIcon = ""
            versions_behind = int(self.server_info_array['kernel'].get('versions_behind', 0))
            try:
                thresholds = self.get_thresholds('kernel_versions_behind')
                if versions_behind >= int(float(thresholds.error)) and int(float(thresholds.error)) != 0:
                    hasError = True
                    stateIndicatingIcon = errorIcon
                elif versions_behind >= int(float(thresholds.warning)) and int(float(thresholds.warning)) != 0:
                    hasWarning = True
                    stateIndicatingIcon = warningIcon
            except Exception:
                pass
            running = self.server_info_array['kernel'].get('running_kernel', 'unknown')
            installed = self.server_info_array['kernel'].get('installed_version', 'unknown')
            candidate = self.server_info_array['kernel'].get('candidate_version', 'unknown')
            if versions_behind > 0:
                kernel_info_str = f"{running} ({installed} → {candidate}, {versions_behind} behind)"
            else:
                kernel_info_str = f"{running} (up to date)"
            serverReport += stateIndicatingIcon + f"<b>Kernel:</b> {wrap_with_code(kernel_info_str)}\n"

        # Add System Restart information with an if-else statement.
        thresholds = self.get_thresholds('system_restart')
        stateIndicatingIcon = ""
        system_value = float(self.server_info_array['system_restart']['time_elapsed_seconds'])
        if system_value > timeStringUtils.convert_time_string_to_seconds(thresholds.error):
            hasError = True
            stateIndicatingIcon = errorIcon
        elif system_value > timeStringUtils.convert_time_string_to_seconds(thresholds.warning):
            hasWarning = True
            stateIndicatingIcon = warningIcon
        restart_info = "No system restart required" if self.server_info_array['system_restart']['status'] == 'No restart required' else \
            f"System restart required for {wrap_with_code(self.server_info_array['system_restart']['time_elapsed_human_readable'])}"
        serverReport += stateIndicatingIcon + f"<b>System Restart:</b> {wrap_with_code(restart_info)}\n"

        # Add Linux Server State Tool information.
        tool_info = ""
        thresholds = self.get_thresholds('linux_server_state_tool')
        stateIndicatingIcon = ""
        # Check remote connection.
        if self.server_info_array['linux_server_state_tool']['repo_accessible'] == "true":

            # Check local changes.
            if self.server_info_array['linux_server_state_tool']['local_changes'] == "Yes":
                tool_info += "Uncommitted local changes, "

            # Is repo up to date?
            git_behind_count = int(self.server_info_array['linux_server_state_tool']['behind_count'])
            if git_behind_count > 0:
                
                system_value = float(self.server_info_array['linux_server_state_tool']['behind_count'])
                if system_value > float(thresholds.error):
                    hasError = True
                    stateIndicatingIcon = errorIcon
                elif system_value > float(thresholds.warning):
                    hasWarning = True
                    stateIndicatingIcon = warningIcon

                tool_info += f"Repo updateable. {git_behind_count} commits behind."
            else:
                tool_info += f"Tool is up to date"
        else:
            tool_info += "Remote repo Not accessible!! Check connection!! repo_accessible: " + self.server_info_array['linux_server_state_tool']['repo_accessible'] 

        serverReport += f"<b>Linux Server State Tool:</b> {wrap_with_code(tool_info)}\n"

        
        # Hardware Metrics (with error handling)
        if 'hardware' in self.server_info_array:
            # CPU Temperature
            thresholds = self.get_thresholds('temperature_cpu')
            stateIndicatingIcon = ""
            cpu_temp_str = self.server_info_array['hardware'].get('cpu_temperature_celsius', 'N/A')
            if cpu_temp_str != 'N/A' and 'not available' not in cpu_temp_str.lower():
                try:
                    system_value = float(cpu_temp_str)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            serverReport += stateIndicatingIcon + f"<b>CPU Temperature:</b> {wrap_with_code(cpu_temp_str)}°C\n"

            # Fan Speed
            fan_speed_str = self.server_info_array['hardware'].get('fan_speed_rpm', 'N/A')
            if fan_speed_str != 'N/A' and 'not available' not in fan_speed_str.lower():
                thresholds = self.get_thresholds('fan_speed')
                stateIndicatingIcon = ""
                try:
                    system_value = float(fan_speed_str)
                    if system_value <= float(thresholds.error) and float(thresholds.error) != 0:
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value <= float(thresholds.warning) and float(thresholds.warning) != 0:
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            serverReport += stateIndicatingIcon + f"<b>Fan Speed:</b> {wrap_with_code(fan_speed_str)} RPM\n"

            # GPU Temperature
            gpu_temp_str = self.server_info_array['hardware'].get('gpu_temperature_celsius', 'N/A')
            if gpu_temp_str != 'N/A' and 'not available' not in gpu_temp_str.lower():
                thresholds = self.get_thresholds('temperature_gpu')
                stateIndicatingIcon = ""
                try:
                    system_value = float(gpu_temp_str)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            serverReport += stateIndicatingIcon + f"<b>GPU Temperature:</b> {wrap_with_code(gpu_temp_str)}°C\n"

        # Performance Metrics
        # I/O Wait
        if 'io_wait' in self.server_info_array:
            thresholds = self.get_thresholds('io_wait')
            stateIndicatingIcon = ""
            io_wait_str = self.server_info_array['io_wait'].get('io_wait_percentage', 'N/A')
            if io_wait_str != 'N/A':
                try:
                    system_value = float(io_wait_str)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            serverReport += stateIndicatingIcon + f"<b>I/O Wait:</b> {wrap_with_code(io_wait_str)}%\n"

        # System Load
        if 'system_load' in self.server_info_array:
            thresholds = self.get_thresholds('system_load_1min')
            stateIndicatingIcon = ""
            load_1min_str = self.server_info_array['system_load'].get('load_1min', 'N/A')
            if load_1min_str != 'N/A':
                try:
                    system_value = float(load_1min_str)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            load_5min_str = self.server_info_array['system_load'].get('load_5min', 'N/A')
            load_15min_str = self.server_info_array['system_load'].get('load_15min', 'N/A')
            load_info = f"{load_1min_str} (1min), {load_5min_str} (5min), {load_15min_str} (15min)"
            serverReport += stateIndicatingIcon + f"<b>System Load:</b> {wrap_with_code(load_info)}\n"

        # File Descriptors
        if 'file_descriptors' in self.server_info_array:
            thresholds = self.get_thresholds('file_descriptors')
            stateIndicatingIcon = ""
            fd_usage_str = self.server_info_array['file_descriptors'].get('usage_percent', 'N/A')
            if fd_usage_str != 'N/A':
                try:
                    system_value = float(fd_usage_str)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            fd_allocated = self.server_info_array['file_descriptors'].get('allocated', 'N/A')
            fd_maximum = self.server_info_array['file_descriptors'].get('maximum', 'N/A')
            fd_info = f"{fd_usage_str}% ({fd_allocated} of {fd_maximum})"
            serverReport += stateIndicatingIcon + f"<b>File Descriptors:</b> {wrap_with_code(fd_info)}\n"

        # Disk SMART Health
        if 'disk_smart' in self.server_info_array:
            smart_status = self.server_info_array['disk_smart'].get('status', 'N/A')
            stateIndicatingIcon = ""
            if smart_status == 'available':
                devices = self.server_info_array['disk_smart'].get('devices', [])
                failed_count = 0
                for device in devices:
                    if device.get('health') == 'failed':
                        failed_count += 1
                thresholds = self.get_thresholds('smart_health_failed')
                if failed_count >= int(float(thresholds.error)):
                    hasError = True
                    stateIndicatingIcon = errorIcon
                elif failed_count >= int(float(thresholds.warning)):
                    hasWarning = True
                    stateIndicatingIcon = warningIcon
            serverReport += stateIndicatingIcon + f"<b>Disk SMART:</b> {wrap_with_code(smart_status)}\n"

        # Storage Arrays (ZFS/RAID)
        if 'storage_arrays' in self.server_info_array:
            zfs_status = self.server_info_array['storage_arrays'].get('zfs', {}).get('status', 'N/A')
            raid_status = self.server_info_array['storage_arrays'].get('raid', {}).get('status', 'N/A')
            stateIndicatingIcon = ""
            
            # Check ZFS
            if zfs_status == 'available':
                pools = self.server_info_array['storage_arrays'].get('zfs', {}).get('pools', [])
                degraded_count = 0
                for pool in pools:
                    if pool.get('health') not in ['ONLINE', 'healthy']:
                        degraded_count += 1
                thresholds = self.get_thresholds('zfs_pool_degraded')
                if degraded_count >= int(float(thresholds.error)):
                    hasError = True
                    stateIndicatingIcon = errorIcon
                elif degraded_count >= int(float(thresholds.warning)):
                    hasWarning = True
                    stateIndicatingIcon = warningIcon
            
            # Check RAID
            if raid_status == 'available':
                arrays = self.server_info_array['storage_arrays'].get('raid', {}).get('arrays', [])
                degraded_count = 0
                for array in arrays:
                    if array.get('state') not in ['clean', 'active', 'optimal']:
                        degraded_count += 1
                thresholds = self.get_thresholds('raid_array_degraded')
                if degraded_count >= int(float(thresholds.error)):
                    hasError = True
                    stateIndicatingIcon = errorIcon
                elif degraded_count >= int(float(thresholds.warning)):
                    hasWarning = True
                    stateIndicatingIcon = warningIcon
            
            serverReport += stateIndicatingIcon + f"<b>Storage Arrays:</b> {wrap_with_code(f'ZFS: {zfs_status}, RAID: {raid_status}')}\n"

        # NTP Sync
        if 'ntp_sync' in self.server_info_array:
            ntp_status = self.server_info_array['ntp_sync'].get('status', 'N/A')
            ntp_offset = self.server_info_array['ntp_sync'].get('offset_ms', 'N/A')
            stateIndicatingIcon = ""
            
            if ntp_offset != 'N/A':
                try:
                    thresholds = self.get_thresholds('ntp_offset_ms')
                    system_value = float(ntp_offset)
                    if system_value >= float(thresholds.error):
                        hasError = True
                        stateIndicatingIcon = errorIcon
                    elif system_value >= float(thresholds.warning):
                        hasWarning = True
                        stateIndicatingIcon = warningIcon
                except (ValueError, TypeError):
                    pass
            
            ntp_info = f"{ntp_status}"
            if ntp_offset != 'N/A':
                ntp_info += f" (offset: {ntp_offset}ms)"
            serverReport += stateIndicatingIcon + f"<b>NTP Sync:</b> {wrap_with_code(ntp_info)}\n"

        
        # Determine overall server state, adapt heading and concenate with rest of report.
        stateIndicatingIcon = ""
        if hasError == True:
            stateIndicatingIcon = errorIcon
        elif hasWarning == True:
            stateIndicatingIcon = warningIcon
        serverHeading = stateIndicatingIcon + f"<b>Server Status Report</b> - {wrap_with_code(self.server_name)}\n"
        serverReport = serverHeading + serverReport

        return ServerReport(serverReport, hasWarning=hasWarning, hasError=hasError)


    def get_thresholds(self, thresholds_key: str) -> Thresholds:
        """Get threshold values for a specific metric from config.

        Args:
            thresholds_key (str): Threshold key (e.g., 'cpu', 'disk').

        Returns:
            Thresholds: Object with warning and error threshold values.
        """
        return self._config.get_thresholds(thresholds_key)
