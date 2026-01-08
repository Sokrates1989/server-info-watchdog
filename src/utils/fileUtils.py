## Basic file operations.

# Interaction with operating system (read write files).
import os

# For string sanitization.
import re

def createFileIfNotExists(fileToCreateIfNotExists):
	"""Create a file (and its parent directories) if it does not exist.

	Args:
		fileToCreateIfNotExists (str): Absolute or relative file path.

	Returns:
		None: This function has no return value.

	Note:
		Uses a portable create strategy (open in append mode) rather than
		os.mknod, because some filesystems/bind-mounts do not support mknod.
	"""
	# Seperate directory from filename.
	if "/" in fileToCreateIfNotExists:
		lastSlashPosition = fileToCreateIfNotExists.rfind("/")

		directoryName = fileToCreateIfNotExists[0:(lastSlashPosition)]
		if not os.path.exists(directoryName):
			os.makedirs(directoryName)
			try:
				os.chmod(directoryName, 0o775)
			except Exception:
				pass

		if not os.path.exists(fileToCreateIfNotExists):
			with open(fileToCreateIfNotExists, 'a+', encoding='utf-8'):
				pass
			try:
				os.chmod(fileToCreateIfNotExists, 0o775)
			except Exception:
				pass
	else:
		print("Cannot create a file without directory (pass filename containing filepath like \"path/to/file.txt\")")


# Get a valid filename for a string.
def getValidFileNameForString(stringToConvertToFileName, fileType):
	"""Convert an arbitrary string into a safe filename.

	Args:
		stringToConvertToFileName (Any): Input string or value to convert.
		fileType (str): File extension (without dot).

	Returns:
		str: Sanitized filename with the provided extension.
	"""
	whiteListedCharactersRegEx = "[^a-zA-Z0-9.\-_]"
	validFilename = re.sub(whiteListedCharactersRegEx, '', str(stringToConvertToFileName) )
	validFilename = validFilename[:100]

	validFilename += "." + str(fileType)
	return validFilename


# Read string from file.
def readStringFromFile(fileToReadStringFrom):
	"""Read a file and return its content as a stripped string.

	Args:
		fileToReadStringFrom (str): Path to the file.

	Returns:
		str: File content with trailing whitespace removed.
	"""
	string = ""
	with open(fileToReadStringFrom, 'r') as file:
		string = file.read().rstrip()
	return string


# Overwrite string of file.
# !!! Completely removes previous content !!!
def overwriteContentOfFile(fileToEdit, newString):
	"""Overwrite a file with the provided string content.

	Args:
		fileToEdit (str): Path to the file.
		newString (Any): Value to write (converted to string).

	Returns:
		None: This function has no return value.
	"""
	createFileIfNotExists(fileToEdit)
	with open(fileToEdit,'w') as f:
		f.write(str(newString))