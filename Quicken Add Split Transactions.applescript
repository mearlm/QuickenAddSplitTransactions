-- Default the file picker directly to your Downloads folder
try
	set downloadsPath to (path to downloads folder)
	set chosenFile to choose file with prompt "Select your Quicken CSV Instruction File:" default location downloadsPath of type {"csv", "txt"}
on error
	return -- User clicked cancel, exit gracefully
end try

-- Read the file content directly into AppleScript memory
set fileText to read chosenFile as «class utf8»
set textLines to paragraphs of fileText
set csvRows to {}

-- Pure AppleScript CSV parsing utility loop
repeat with aLine in textLines
	set cleanLine to my trimText(aLine)
	-- Skip empty lines and comment lines
	if (length of cleanLine > 0) and (character 1 of cleanLine is not "#") then
		set rowItems to my parseCSVLine(cleanLine)
		if (count of rowItems) > 0 then
			copy rowItems to end of csvRows
		end if
	end if
end repeat

-- SANITY CHECK: Ensure we actually found instructions to process
if (count of csvRows) is equal to 0 then
	display dialog "The script parsed your file successfully, but found 0 valid instructions. Please check that your CSV is not empty or entirely commented out." buttons {"OK"} default button 1
	return
end if

-- Direct Application focus shift
tell application "Quicken" to activate
delay 1.0 -- Solid 1-second pause to let the Quicken UI finish drawing forward

set isFirstSplit to true

-- Main Processing Engine Loop
repeat with targetRow in csvRows
	set commandType to item 1 of targetRow
	
	---------------------------------------------------------------------
	-- CASE 1: Start a New Transaction
	---------------------------------------------------------------------
	if commandType is "NewTransaction" then
		set txDate to item 2 of targetRow
		set txPayee to item 3 of targetRow
		set txAmount to item 4 of targetRow
		set isFirstSplit to true
		
		tell application "System Events"
			tell process "Quicken"
				-- 1. Cmd+N to start new row
				keystroke "n" using {command down}
				delay 0.3
				
				-- 2. Type Date -> Tab to Payee
				keystroke txDate
				keystroke tab
				delay 0.2
				
				-- 3. Type Payee -> Tab to Category
				keystroke txPayee
				keystroke tab
				delay 0.2
				
				-- 4. Tab past Category (leave blank) to Amount field
				keystroke tab
				delay 0.2
				
				-- 5. Type Total Amount
				keystroke txAmount
				delay 0.2
				
				-- 6. Open Split dialog (Cmd+Opt+S)
				keystroke "s" using {command down, option down}
				delay 0.8
				
				-- 7. Tab into the first Category line inside Split Editor
				keystroke tab
				delay 0.2
			end tell
		end tell
		
		---------------------------------------------------------------------
		-- CASE 2: Process an Individual Split Row
		---------------------------------------------------------------------
	else if commandType is "Split" then
		set splitCategory to item 2 of targetRow
		
		if (count of targetRow) is equal to 4 then
			set splitTransfer to item 3 of targetRow
			set splitAmount to item 4 of targetRow
		else
			set splitTransfer to ""
			set splitAmount to item 3 of targetRow
		end if
		
		tell application "System Events"
			tell process "Quicken"
				-- If NOT the first split line, insert a new row (Shift+Cmd+N)
				if not isFirstSplit then
					keystroke "n" using {command down, shift down}
					delay 0.4
				end if
				
				-- Type Split Category -> Tab past Tags field
				keystroke splitCategory
				keystroke tab
				delay 0.2
				keystroke tab
				delay 0.2
				
				-- Input Transfer if specified, otherwise tab past it
				if splitTransfer is not "" then
					keystroke splitTransfer
					delay 0.1
				end if
				keystroke tab
				delay 0.2
				
				-- Input Split Amount
				keystroke splitAmount
				delay 0.2
			end tell
		end tell
		
		-- Toggle the split tracker flag for subsequent rows
		set isFirstSplit to false
		
		---------------------------------------------------------------------
		-- CASE 3: Save and Commit Transaction
		---------------------------------------------------------------------
	else if commandType is "SaveTransaction" then
		ignoring application responses
			tell application "System Events"
				tell process "Quicken"
					-- One single return closes the balanced split sub-window and commits the transaction
					keystroke return
					delay 0.2
				end tell
			end tell
		end ignoring
	end if
end repeat

-- AUTOMATED ARCHIVE CLEANUP (Optional)
try
	-- Create a text timestamp string (YYYY-MM-DD_HHMMSS)
	set curDate to (current date)
	set ymd to (year of curDate as text) & "-" & text -2 thru -1 of ("0" & (month of curDate as integer)) & "-" & text -2 thru -1 of ("0" & day of curDate)
	set hms to text -2 thru -1 of ("0" & hours of curDate) & text -2 thru -1 of ("0" & minutes of curDate) & text -2 thru -1 of ("0" & seconds of curDate)
	set timestamp to ymd & "_" & hms
	
	-- Establish paths for the original file and target folder
	set originalFile to chosenFile
	set archiveFolderPath to (POSIX path of downloadsPath) & "Quicken_Archive/"
	
	-- Silently build the archive directory folder if it doesn't already exist
	do shell script "mkdir -p " & quoted form of archiveFolderPath
	
	-- Calculate the name changes
	tell application "System Events"
		set oldName to name of originalFile
		set ext to name extension of originalFile
		set baseName to text 1 thru -((length of ext) + 2) of oldName
		set newName to baseName & "_" & timestamp & "." & ext
	end tell
	
	-- Move and rename the processed file via background shell commands
	set destinationPath to archiveFolderPath & newName
	do shell script "mv " & quoted form of csvFilePath & " " & quoted form of destinationPath
on error
	-- If archiving encounters an error, ignore it so the main script alert still prints
end try

-- Completion alert
display dialog "Data entry automation sequence completed successfully!" buttons {"Finished"} default button 1


---------------------------------------------------------------------
-- HELPER UTILITIES: Text Processing & CSV Logic
---------------------------------------------------------------------
on trimText(txt)
	set d to AppleScript's text item delimiters
	set AppleScript's text item delimiters to {space, tab, return, character id 10, character id 13}
	set textItems to text items of txt
	set cleanItems to {}
	repeat with itemPtr in textItems
		if length of itemPtr > 0 then copy contents of itemPtr to end of cleanItems
	end repeat
	set AppleScript's text item delimiters to space
	set combinedText to cleanItems as string
	set AppleScript's text item delimiters to d
	return combinedText
end trimText

on parseCSVLine(csvLine)
	set parsedFields to {}
	set currentField to ""
	set insideQuotes to false
	
	repeat with i from 1 to count of csvLine
		set char to character i of csvLine
		if char is "\"" then
			set insideQuotes to not insideQuotes
		else if char is "," and not insideQuotes then
			copy my stripLeadingTrailingSpace(currentField) to end of parsedFields
			set currentField to ""
		else
			set currentField to currentField & char
		end if
	end repeat
	copy my stripLeadingTrailingSpace(currentField) to end of parsedFields
	return parsedFields
end parseCSVLine

on stripLeadingTrailingSpace(txt)
	if txt is "" then return ""
	repeat while txt starts with " " or txt starts with tab
		if length of txt > 1 then
			set txt to text 2 thru -1 of txt
		else
			return ""
		end if
	end repeat
	repeat while txt ends with " " or txt ends with tab
		if length of txt > 1 then
			set txt to text 1 thru -2 of txt
		else
			return ""
		end if
	end repeat
	return txt
end stripLeadingTrailingSpace

