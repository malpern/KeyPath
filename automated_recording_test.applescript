-- Automated KeyPath Recording Test
-- Uses accessibility identifiers for reliable UI automation
-- Tests both regular and debug recording buttons

tell application "KeyPath"
    activate
    delay 2
end tell

tell application "System Events"
    tell process "KeyPath"
        try
            -- Log the start of our test
            do shell script "echo '🤖 [AppleScript] Starting automated recording test' >> /tmp/keypath_automation.log"
            do shell script "echo '🤖 [AppleScript] Test started at: ' && date >> /tmp/keypath_automation.log"
            
            -- Test 1: Try the debug force recording button (should always work)
            do shell script "echo '🤖 [AppleScript] TEST 1: Clicking debug force recording button' >> /tmp/keypath_automation.log"
            
            set debugButton to button "debug-force-record-button" of UI element "debug-recording-section"
            click debugButton
            delay 1
            
            do shell script "echo '🤖 [AppleScript] Debug button clicked - simulating key press' >> /tmp/keypath_automation.log"
            
            -- Simulate pressing the 'a' key
            key code 0 -- 'a' key
            delay 1
            
            -- Test 2: Try the regular record button
            do shell script "echo '🤖 [AppleScript] TEST 2: Clicking regular record button' >> /tmp/keypath_automation.log"
            
            set regularButton to button "input-key-record-button" of UI element "input-recording-section"
            click regularButton
            delay 1
            
            do shell script "echo '🤖 [AppleScript] Regular button clicked - simulating key press' >> /tmp/keypath_automation.log"
            
            -- Simulate pressing the 'b' key
            key code 11 -- 'b' key
            delay 1
            
            -- Test 3: Use keyboard shortcuts
            do shell script "echo '🤖 [AppleScript] TEST 3: Testing Cmd+R keyboard shortcut' >> /tmp/keypath_automation.log"
            
            key code 15 using {command down} -- Cmd+R
            delay 1
            
            do shell script "echo '🤖 [AppleScript] Cmd+R pressed - simulating key press' >> /tmp/keypath_automation.log"
            
            -- Simulate pressing the 'c' key
            key code 8 -- 'c' key
            delay 1
            
            -- Test 4: Use debug keyboard shortcut
            do shell script "echo '🤖 [AppleScript] TEST 4: Testing Cmd+Shift+T debug shortcut' >> /tmp/keypath_automation.log"
            
            key code 17 using {command down, shift down} -- Cmd+Shift+T
            delay 1
            
            do shell script "echo '🤖 [AppleScript] Cmd+Shift+T pressed - simulating key press' >> /tmp/keypath_automation.log"
            
            -- Simulate pressing the 'd' key
            key code 2 -- 'd' key
            delay 1
            
            do shell script "echo '🤖 [AppleScript] All tests completed successfully' >> /tmp/keypath_automation.log"
            
        on error errMsg
            do shell script "echo '❌ [AppleScript] Error during automation: " & errMsg & "' >> /tmp/keypath_automation.log"
        end try
        
    end tell
end tell

do shell script "echo '🤖 [AppleScript] Automation test finished - check KeyPath logs for results' >> /tmp/keypath_automation.log"