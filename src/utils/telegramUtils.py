## Utilities for telegram usage such as sending messages.

# For getting current timestamp.
import time
# For file operations with operating system.
import os
# For creating files.
import fileUtils
# To interact with telgram bots.
import telebot

## Own classes.
import stringUtils
from watchdogConfig import get_config


def _is_truthy_env(env_var_name: str) -> bool:
    """Return True if the given environment variable is set to a truthy value.

    Args:
        env_var_name (str): Name of the environment variable.

    Returns:
        bool: True if the environment variable exists and is set to a typical
            truthy value (e.g. "1", "true", "yes"), otherwise False.
    """

    value = os.getenv(env_var_name)
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}

# Load config from environment/watchdog.env.
_config = get_config()

# Fetch botToken from secret file, if existing.
botToken = ""
BOT_TOKEN_FILE = os.getenv("botToken_FILE") or os.getenv("TELEGRAM_BOT_TOKEN_FILE")

if BOT_TOKEN_FILE:
    try:
        with open(BOT_TOKEN_FILE, "r") as bot_token_file:
            botToken = bot_token_file.read().strip()
    except FileNotFoundError:
        botToken = ""

if not botToken:
    botToken = (os.getenv("botToken") or os.getenv("TELEGRAM_BOT_TOKEN") or "").strip().strip("\"")

telegram_disabled = (
    _is_truthy_env("DISABLE_TELEGRAM")
    or (not botToken)
    or botToken.strip() in {"change_me_telegram_token", "CHANGE_ME_TELEGRAM_TOKEN"}
)

# Initialize telegram bot.
bot = None
if not telegram_disabled:
    bot = telebot.TeleBot(botToken, parse_mode="HTML")

# Telegram Chats were to send info, error and warnings to (loaded from config).
errorChatIDs = []
warningChatIDs = []
infoChatIDs = []

if not telegram_disabled:
    # Get chat IDs from config (already parsed and sanitized).
    errorChatIDs = _config.error_chat_ids
    warningChatIDs = _config.warning_chat_ids
    infoChatIDs = _config.info_chat_ids

    # Ensure, that there is at least one item in each chat-group.
    if not any(errorChatIDs):
        raise ValueError("At least one item is required in errorChatIDs.")
    if not any(warningChatIDs):
        raise ValueError("At least one item is required in warningChatIDs.")
    if not any(infoChatIDs):
        raise ValueError("At least one item is required in infoChatIDs.")



# Send Error message.
def sendErrorMessage(errorMessage):
    """Send an error message to all configured Telegram error chats."""
    for errorChatID in errorChatIDs:
        sendMessage(errorChatID, errorMessage)

# Send Warning message.
def sendWarningMessage(warningMessage):
    """Send a warning message to all configured Telegram warning chats."""
    for warningChatID in warningChatIDs:
        sendMessage(warningChatID, warningMessage)

# Send Info message.
def sendInfoMessage(infoMessage):
    """Send an info message to all configured Telegram info chats."""
    for infoChatID in infoChatIDs:
        sendMessage(infoChatID, infoMessage)

# Send message using telegram.
def sendMessage(chatID, message):
    """Send a single message to a Telegram chat.

    Args:
        chatID (str): Telegram chat ID.
        message (str): Message text (HTML is supported).

    Returns:
        None: This function has no return value.
    """

    if telegram_disabled:
        return

    # Recreate bot to avoid timeout errors.
    bot = telebot.TeleBot(botToken, parse_mode="HTML")
    
    # Does message have to be split?
    if len(message) > 4096:
        # Split message.
        individualMessages = stringUtils.splitLongTextIntoWorkingMessages(message)

        # Send messages.
        for individualMessage in individualMessages:
            bot.send_message(chatID, individualMessage)

    else:
        bot.send_message(chatID, message)
