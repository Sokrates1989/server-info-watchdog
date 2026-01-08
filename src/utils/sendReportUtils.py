## Utilities for report or info message creation.

# For getting current timestamp.
import time
# For file operations with operating system.
import os
# To create enumerations.
from enum import Enum

## Own classes.
from serverReport import ServerReport
from serverReport import MostCrucialServerState
import telegramUtils
import fileUtils
import timeStringUtils
from watchdogConfig import get_config

class MessagingPlatform(Enum):
    DEFAULT = "Default"
    EMAIL = "Email"
    TELEGRAM = "Telegram"

# Load config from environment/watchdog.env.
_config = get_config()

# Path to serverInfo and last sent files.
_env_state_dir = os.getenv("WATCHDOG_STATE_DIR")
_project_root = os.path.join(os.path.dirname(__file__), "..", "..")
_server_info_dir = os.path.join(_project_root, "serverInfo")

if _env_state_dir:
    state_dir = _env_state_dir
elif os.path.isdir(_server_info_dir) and os.access(_server_info_dir, os.W_OK):
    state_dir = os.path.join(_server_info_dir, "state")
else:
    state_dir = os.path.join(_project_root, "logs", "state")
lastSentInfoFile = os.path.join(state_dir, "lastSentInfoReport.txt")
lastSentWarningFile = os.path.join(state_dir, "lastSentWarningReport.txt")
lastSentErrorFile = os.path.join(state_dir, "lastSentErrorReport.txt")

# Message frequency from config.
maxInfoReportFrequencySeconds = timeStringUtils.convert_time_string_to_seconds(
    _config.get_message_frequency('info')
)
maxWarningReportFrequencySeconds = timeStringUtils.convert_time_string_to_seconds(
    _config.get_message_frequency('warning')
)
maxErrorReportFrequencySeconds = timeStringUtils.convert_time_string_to_seconds(
    _config.get_message_frequency('error')
)


# Send server report based on state and last sent report date.
def sendServerReport(serverReport: ServerReport, messagePlatform: MessagingPlatform = MessagingPlatform.DEFAULT):

    """Send server reports (info/warning/error) based on thresholds and frequency.

    Args:
        serverReport (ServerReport): Prepared report with state classification.
        messagePlatform (MessagingPlatform, optional): Currently unused selector
            for potential future message platform routing. Defaults to
            MessagingPlatform.DEFAULT.

    Returns:
        None: This function has no return value.
    """

    if shouldInfoReportBeSent():
        sendInfoReport(serverReport.getServerReportMessage())
    
    if shouldWarningReportBeSent(serverReport.getMostCrucialState()):
        sendWarningReport(serverReport.getServerReportMessage())
    
    if shouldErrorReportBeSent(serverReport.getMostCrucialState()):
        sendErrorReport(serverReport.getServerReportMessage())
    


# Should the info report be sent.
def shouldInfoReportBeSent():

    """Check whether the next info report should be sent.

    Returns:
        bool: True if enough time elapsed since the last sent info report.
    """

    lastSentInfoUnixTimestamp = getLastSentUnixTimestamp(lastSentInfoFile)
    if lastSentInfoUnixTimestamp + maxInfoReportFrequencySeconds < int(time.time()):
        return True
    else:
        return False


# Send info report and write last sent state to file.
def sendInfoReport(reportMessage):

    """Send an info report and persist its last-sent timestamp.

    Args:
        reportMessage (str): Message body.

    Returns:
        None: This function has no return value.
    """

    # Send Info Report Message.
    telegramUtils.sendInfoMessage(reportMessage)

    # Write to file when the last Info report message has been sent.
    fileUtils.overwriteContentOfFile(lastSentInfoFile, time.time())


    
# Should the warning report be sent.
def shouldWarningReportBeSent(mostCrucialServerState: MostCrucialServerState):
    """Check whether the next warning report should be sent.

    Args:
        mostCrucialServerState (MostCrucialServerState): Current server state.

    Returns:
        bool: True if state is at least WARNING and frequency allows sending.
    """

    # Is most crucial server state at least warning?
    if mostCrucialServerState == MostCrucialServerState.WARNING or mostCrucialServerState == MostCrucialServerState.ERROR:
        # Are frequency limits reached.
        lastSentWarningUnixTimestamp = getLastSentUnixTimestamp(lastSentWarningFile)
        if lastSentWarningUnixTimestamp + maxWarningReportFrequencySeconds < int(time.time()):
            return True
        else:
            return False
    else:
        return False

# Send warning report and write last sent state to file.
def sendWarningReport(reportMessage):

    """Send a warning report and persist its last-sent timestamp.

    Args:
        reportMessage (str): Message body.

    Returns:
        None: This function has no return value.
    """
    
    # Send Warning Report Message.
    telegramUtils.sendWarningMessage(reportMessage)

    # Write to file when the last Warning report message has been sent.
    fileUtils.overwriteContentOfFile(lastSentWarningFile, time.time())


    
# Should the error report be sent.
def shouldErrorReportBeSent(mostCrucialServerState: MostCrucialServerState):
    """Check whether the next error report should be sent.

    Args:
        mostCrucialServerState (MostCrucialServerState): Current server state.

    Returns:
        bool: True if state is ERROR and frequency allows sending.
    """

    # Is most crucial server state Error?
    if mostCrucialServerState == MostCrucialServerState.ERROR:
        # Are frequency limits reached.
        lastSentErrorUnixTimestamp = getLastSentUnixTimestamp(lastSentErrorFile)
        if lastSentErrorUnixTimestamp + maxErrorReportFrequencySeconds < int(time.time()):
            return True
        else:
            return False
    else:
        return False
    
# Send error report and write last sent state to file.
def sendErrorReport(reportMessage):

    """Send an error report and persist its last-sent timestamp.

    Args:
        reportMessage (str): Message body.

    Returns:
        None: This function has no return value.
    """
    
    # Send Error Report Message.
    telegramUtils.sendErrorMessage(reportMessage)

    # Write to file when the last error report message has been sent.
    fileUtils.overwriteContentOfFile(lastSentErrorFile, time.time())


# Get last sent time.
def getLastSentUnixTimestamp(fileToGetTimeStampOf) -> int:

    """Read last-sent timestamp from a file.

    Args:
        fileToGetTimeStampOf (str): Path to the timestamp file.

    Returns:
        int: Unix timestamp, or 0 if file does not exist or cannot be parsed.
    """
    try:
        content = fileUtils.readStringFromFile(fileToGetTimeStampOf)
        float_value = float(content)
        return int(float_value)
    except Exception as e:
        print(f"getLastSentUnixTimestamp File does not exist or could not be converted to valid unixtimestamp, returning 0: {e}")
        return 0
