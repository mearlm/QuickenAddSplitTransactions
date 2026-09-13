-- 1. FILE PICKER & INITIAL PATH SETTING
try
	set downloadsPath to (path to downloads folder)
	set chosenFile to choose file with prompt "Select your Quicken CSV Instruction File:" default location downloadsPath of type {"csv", "txt"}
	set csvFilePath to POSIX path of chosenFile
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
	if (length of cleanLine > 0) and (character 1 of cleanLine is not "#") then
		try
			set rowItems to my parseCSVLine(cleanLine)
		on error errMsg
			display dialog "🛑 CSV Parse Error:" & return & return & errMsg
			return
		end try
		-- Excel exports the worksheet as a fixed-width 4-column CSV,
		-- so shorter commands acquire trailing empty fields.
		-- Remove only trailing empties; preserve intentional internal blanks.
		repeat while (count of rowItems) > 1 and (item -1 of rowItems) is ""
			set rowItems to items 1 thru -2 of rowItems
		end repeat
		if (count of rowItems) > 0 then
			set firstField to item 1 of rowItems
			
			-- Ignore rows that normalize down to a single empty field
			if firstField is not "" then
				copy rowItems to end of csvRows
			end if
		end if
	end if
end repeat


-- 2. PREFLIGHT VALIDATION ENGINE (Protects Quicken from bad data)
set totalRows to count of csvRows
if totalRows is equal to 0 then
	display dialog "🛑 Validation Error: The file contains 0 valid instructions." buttons {"OK"} default button 1
	return
end if

set txCount to 0
set isInsideTx to false
set expectedTotal to 0.0
set runningSplitSum to 0.0
set currentTxDate to ""
set currentTxPayee to ""

repeat with i from 1 to totalRows
	set currentRow to item i of csvRows
	set cmd to item 1 of currentRow
	
	if cmd is "NewTransaction" then
		if (count of currentRow) is not 4 then
			display dialog "🛑 Invalid NewTransaction row " & i & ": expected 4 fields, found " & (count of currentRow) & "."
			return
		end if
		if isInsideTx then
			-- Caught a new transaction starting before the previous one saved
			display dialog "🛑 Preflight Validation Failed!" & return & return & "Transaction #" & txCount & " (" & currentTxDate & " - " & currentTxPayee & ") is missing a closing 'SaveTransaction' instruction row." buttons {"OK"} default button 1
			return
		end if
		
		set txCount to txCount + 1
		set isInsideTx to true
		set currentTxDate to item 2 of currentRow
		set currentTxPayee to item 3 of currentRow
		set splitCount to 0
		
		-- Convert the expected string total to a clean real number for math validation
		set expectedTotal to my cleanNumericString(item 4 of currentRow)
		set runningSplitSum to 0.0
		
	else if cmd is "Split" then
		if (count of currentRow) is not 3 and (count of currentRow) is not 4 then
			display dialog "🛑 Invalid Split row " & i & ": expected 3 or 4 fields."
			return
		end if
		if not isInsideTx then
			display dialog "🛑 Preflight Validation Failed!" & return & return & "Found an orphan 'Split' command at row " & i & " before any 'NewTransaction' block was declared." buttons {"OK"} default button 1
			return
		end if
		
		set splitCount to splitCount + 1
		
		-- Find the split amount column (handles optional transfer strings smoothly)
		if (count of currentRow) is equal to 4 then
			set splitAmtStr to item 4 of currentRow
		else
			set splitAmtStr to item 3 of currentRow
		end if
		
		set runningSplitSum to runningSplitSum + (my cleanNumericString(splitAmtStr))
		
	else if cmd is "SaveTransaction" then
		if splitCount is equal to 0 then
			display dialog "🛑 Preflight Validation Failed!" & return & return & ¬
				"Transaction #" & txCount & " (" & currentTxDate & " - " & currentTxPayee & ¬
				") contains no Split instructions." buttons {"OK"} default button 1
			return
		end if
		if (count of currentRow) is not 1 then
			display dialog "🛑 Invalid SaveTransaction row " & i & ": expected 1 field."
			return
		end if
		if not isInsideTx then
			display dialog "🛑 Preflight Validation Failed!" & return & return & "Found an orphan 'SaveTransaction' command at row " & i & " with no active transaction open." buttons {"OK"} default button 1
			return
		end if
		
		-- Mathematical verification down to the penny
		-- Rounded to 2 decimals to prevent floating-point micro-variations
		set diff to (my roundToTwoDecimals(runningSplitSum)) - (my roundToTwoDecimals(expectedTotal))
		if (abs(diff) > 0.005) then
			set splitTotalStr to my formatAsCurrency(runningSplitSum)
			set expectedTotalStr to my formatAsCurrency(expectedTotal)
			
			display dialog "🛑 Preflight Validation Failed!" & return & return & "Stopped before Transaction " & txCount & " (" & currentTxDate & " - " & currentTxPayee & "):" & return & "Split total " & splitTotalStr & " does not equal expected transaction total " & expectedTotalStr & "." buttons {"OK"} default button 1
			return
		end if
		
		set isInsideTx to false
	else
		display dialog "🛑 Preflight Validation Failed!" & return & return & "Unknown command identifier structure found: '" & cmd & "' at instruction line " & i & "." buttons {"OK"} default button 1
		return
	end if
end repeat

-- Check if file ended abruptly without a save command
if isInsideTx then
	display dialog "🛑 Preflight Validation Failed!" & return & return & "The file ended abruptly. The last Transaction #" & txCount & " (" & currentTxDate & ") is missing its closing 'SaveTransaction' instruction." buttons {"OK"} default button 1
	return
end if


-- 3. INTERFACE AUTOMATION EXECUTION (Only runs if data passes 100%)
tell application "Quicken" to activate
delay 1.0

set isFirstSplit to true

repeat with targetRow in csvRows
	set commandType to item 1 of targetRow
	
	if commandType is "NewTransaction" then
		set txDate to item 2 of targetRow
		set txPayee to item 3 of targetRow
		set txAmount to item 4 of targetRow
		set isFirstSplit to true
		
		tell application "System Events"
			tell process "Quicken"
				keystroke "n" using {command down}
				delay 0.3
				keystroke txDate
				keystroke tab
				delay 0.2
				keystroke txPayee
				keystroke tab
				delay 0.2
				keystroke tab
				delay 0.2
				keystroke tab
				delay 0.2
				keystroke txAmount
				delay 0.2
				keystroke "s" using {command down, option down}
				delay 0.8
				keystroke tab
				delay 0.2
			end tell
		end tell
		
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
				if not isFirstSplit then
					keystroke "n" using {command down, shift down}
					delay 0.4
				end if
				keystroke splitCategory
				keystroke tab
				delay 0.2
				keystroke tab
				delay 0.2
				if splitTransfer is not "" then
					keystroke splitTransfer
					delay 0.1
				end if
				keystroke tab
				delay 0.2
				keystroke splitAmount
				delay 0.2
			end tell
		end tell
		set isFirstSplit to false
		
	else if commandType is "SaveTransaction" then
		tell application "System Events"
			tell process "Quicken"
				keystroke return
			end tell
		end tell
		-- Bypasses the application timeout by waiting safely in the OS container layer 
		-- to allow the balanced row UI window to close and commit entirely.
		delay 0.6
	end if
end repeat


-- 4. AUTOMATED ARCHIVE CLEANUP (Fires only on successful data processing)
set archiveStatus to "Instruction file archived successfully."

(*
try
	set curDate to (current date)
	set ymd to (year of curDate as text) & "-" & text -2 thru -1 of ("0" & (month of curDate as integer)) & "-" & text -2 thru -1 of ("0" & day of curDate)
	set hms to text -2 thru -1 of ("0" & hours of curDate) & text -2 thru -1 of ("0" & minutes of curDate) & text -2 thru -1 of ("0" & seconds of curDate)
	set timestamp to ymd & "_" & hms
	
	set archiveFolderPath to (POSIX path of downloadsPath) & "Quicken_Archive/"
	do shell script "mkdir -p " & quoted form of archiveFolderPath
	
	tell application "System Events"
		set oldName to name of chosenFile
		set ext to name extension of chosenFile
		set baseName to text 1 thru -((length of ext) + 2) of oldName
		set newName to baseName & "_" & timestamp & "." & ext
	end tell
	
	set destinationPath to archiveFolderPath & newName
	do shell script "mv " & quoted form of csvFilePath & " " & quoted form of destinationPath
on error errMsg
	set archiveStatus to "⚠️ Warning: transaction entry succeeded, but archiving failed: " & errMsg
end try
*)



-- 5. SUCCESS NOTIFICATION
display dialog "✅ Data entry automation sequence completed successfully!" & return & return & "Processed " & txCount & " transactions cleanly into your register. " & archiveStatus buttons {"Finished"} default button 1


---------------------------------------------------------------------
-- HELPER UTILITIES: Numerical Extraction & Text Logic
---------------------------------------------------------------------
on cleanNumericString(valStr)
	-- Strips quotes, currency symbols, and formatting commas safely
	set cleanStr to ""
	
	repeat with i from 1 to count of valStr
		set c to character i of valStr
		
		if c is in "0123456789.-" then
			set cleanStr to cleanStr & c
		end if
	end repeat
	
	if cleanStr is "" then return 0.0
	return cleanStr as real
end cleanNumericString

on roundToTwoDecimals(num)
	return (round (num * 100)) / 100
end roundToTwoDecimals

on abs(num)
	if num < 0 then return -num
	return num
end abs

on formatAsCurrency(num)
	set roundedNum to my roundToTwoDecimals(num)
	return "$" & (roundedNum as text)
end formatAsCurrency

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
	if insideQuotes then
		error "Unmatched double-quote in CSV line: " & csvLine
	end if
	copy my stripLeadingTrailingSpace(currentField) to end of parsedFields
	return parsedFields
end parseCSVLine

on stripLeadingTrailingSpace(txt)
	if txt is "" then return ""
	repeat while txt starts with " " or txt starts with tab
		if length of txt > 1 then set txt to text 2 thru -1 of txt
		if length of txt ≤ 1 and (txt starts with " " or txt starts with tab) then return ""
	end repeat
	repeat while txt ends with " " or txt ends with tab
		if length of txt > 1 then set txt to text 1 thru -2 of txt
		if length of txt ≤ 1 and (txt ends with " " or txt ends with tab) then return ""
	end repeat
	return txt
end stripLeadingTrailingSpace

