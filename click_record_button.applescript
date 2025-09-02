-- AppleScript to click the record button in KeyPath
-- This will help test the recording functionality automatically

tell application "KeyPath"
    activate
    delay 1
end tell

tell application "System Events"
    tell process "KeyPath"
        -- Try to find and click the record button
        -- The exact UI element names may vary
        try
            -- Look for a button with record-related text or icon
            set recordButton to first button whose description contains "record" or name contains "record"
            click recordButton
            delay 0.5
            
            -- Log that we clicked
            do shell script "echo '🤖 [AppleScript] Clicked record button' >> /tmp/keypath_test.log"
            
        on error errMsg
            -- If we can't find by description, try finding any button in the input area
            try
                -- Look for text fields first to find the input area
                set inputField to first text field
                -- Then look for nearby buttons
                set allButtons to every button
                if (count of allButtons) > 0 then
                    click item 1 of allButtons
                    do shell script "echo '🤖 [AppleScript] Clicked first button (likely record)' >> /tmp/keypath_test.log"
                end if
            on error errMsg2
                do shell script "echo '🤖 [AppleScript] Could not find record button: " & errMsg2 & "' >> /tmp/keypath_test.log"
            end try
        end try
        
        -- Wait a moment, then simulate pressing a key
        delay 1
        
        -- Simulate pressing the 'a' key
        key code 0 -- 'a' key
        delay 0.5
        
        do shell script "echo '🤖 [AppleScript] Simulated pressing 'a' key' >> /tmp/keypath_test.log"
        
    end tell
end tell

do shell script "echo '🤖 [AppleScript] Test completed - check KeyPath logs' >> /tmp/keypath_test.log"