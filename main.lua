require "import"
import "android.widget.*"
import "android.view.*"
import "android.os.*"
import "java.io.*"
import "android.app.AlertDialog"
import "android.content.Intent"
import "android.net.Uri"
import "android.util.Base64"
import "android.text.TextWatcher"
import "android.graphics.drawable.GradientDrawable"
import "android.content.Context"
import "android.widget.Toast"
import "com.androlua.Http"
import "android.widget.ListView"
import "android.widget.ArrayAdapter"
import "android.widget.SearchView"
import "android.view.inputmethod.InputMethodManager"
import "cjson"
import "android.graphics.Color"
import "android.provider.MediaStore"
import "android.app.DownloadManager"
import "android.text.InputType"
import "android.widget.LinearLayout$LayoutParams"
import "android.graphics.Typeface"
import "java.net.URLEncoder"
import "java.lang.System"
import "android.media.ToneGenerator"
import "android.media.AudioManager"

local String = luajava.bindClass("java.lang.String")
local JBase64 = luajava.bindClass("android.util.Base64")
local File = luajava.bindClass("java.io.File")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
local FileWriter = luajava.bindClass("java.io.FileWriter")
local BufferedWriter = luajava.bindClass("java.io.BufferedWriter")
local BufferedReader = luajava.bindClass("java.io.BufferedReader")
local FileReader = luajava.bindClass("java.io.FileReader")
local Thread = luajava.bindClass("java.lang.Thread")

local sdCard = tostring(Environment.getExternalStorageDirectory())
local EXT_PATH = sdCard .. "/解说/Plugins/"
local TOOL_PATH = sdCard .. "/解说/Tools/"

local appName = "Auto Update Injector By Tech For V I"

-- About & Support Server Configuration
local BASE_URL = "https://jieshuo-resources-for-coding-by-tec.vercel.app/"
local SERVER_FILES = {
    ["About & Support"] = "ABOUT & SUPPORT",
}

-- cachedDescription متغیر
local cachedDescription = "Auto Update Injector Professional - Inject auto update functionality into your plugins with sound, vibration, and new features support."

local DESCRIPTION_URL = "https://raw.githubusercontent.com/TechForVI/Auto-Update-Injector/main/Description"

_G.APP_NAME = "Auto Update Injector By Tech For V I"
_G.shouldShowMain = true

local function trim(s)
    if s == nil then return "" end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

local function showMsg(text)
    Toast.makeText(service, text, Toast.LENGTH_SHORT).show()
end

local function speakMsg(text)
    if service and service.speak then
        service.speak(tostring(text))
    end
end

local function convertToRawUrl(url)
    if url:match("github.com") and not url:match("raw.githubusercontent.com") then
        url = url:gsub("github.com", "raw.githubusercontent.com")
        url = url:gsub("/blob/", "/")
    end
    return url
end

-- Preloaded data
local preloadedAboutSupport = nil
local preloadComplete = false

local function preloadAboutSupport()
    Thread(luajava.bindClass("java.lang.Runnable"){
        run = function()
            Http.get(BASE_URL .. "ABOUT & SUPPORT", function(code, response)
                if code == 200 and response and trim(response) ~= "" then
                    local finalResponse = "local descriptionText = [[" .. cachedDescription:gsub("%]", "] ]") .. "]]\n\n" .. response
                    preloadedAboutSupport = finalResponse
                    preloadComplete = true
                end
            end)
        end
    }).start()
end

local function loadAndExecuteFromServer(fileName, optionTitle)
    if optionTitle == "About & Support" then
        if preloadComplete and preloadedAboutSupport then
            local chunk, err = load(preloadedAboutSupport, "=" .. fileName, "t", _G)
            if chunk then
                local success, execErr = pcall(chunk)
                if not success then
                    speakMsg("No internet connection. Please check your internet connection and try again later.")
                    return
                end
            else
                speakMsg("No internet connection. Please check your internet connection and try again later.")
                return
            end
            return
        end
    end
    
    local loadingDialog = LuaDialog(service)
    loadingDialog.setTitle("Loading...")
    loadingDialog.setMessage("Fetching " .. optionTitle .. " from server...")
    loadingDialog.setCancelable(false)
    loadingDialog.show()

    Http.get(BASE_URL .. fileName, function(code, response)
        Handler(Looper.getMainLooper()).post(Runnable{
            run=function()
                loadingDialog.dismiss()
                if code == 200 and response and trim(response) ~= "" then
                    local finalResponse = response
                    if optionTitle == "About & Support" then
                        finalResponse = "local descriptionText = [[" .. cachedDescription:gsub("%]", "] ]") .. "]]\n\n" .. response
                    end
                    
                    local chunk, err = load(finalResponse, "=" .. fileName, "t", _G)
                    if chunk then
                        local success, execErr = pcall(chunk)
                        if not success then
                            speakMsg("No internet connection. Please check your internet connection and try again later.")
                            return
                        end
                    else
                        speakMsg("No internet connection. Please check your internet connection and try again later.")
                        return
                    end
                else
                    speakMsg("No internet connection. Please check your internet connection and try again later.")
                    return
                end
            end
        })
    end)
end

local function createServerButtonHandler(optionTitle)
    return function()
        local fileName = SERVER_FILES[optionTitle]
        if fileName then
            loadAndExecuteFromServer(fileName, optionTitle)
        else
            showMsg("No server file configured for: " .. optionTitle)
        end
    end
end

Thread(luajava.bindClass("java.lang.Runnable"){
    run = function()
        Http.get(DESCRIPTION_URL, function(code, response)
            if code == 200 and response and trim(response) ~= "" then
                cachedDescription = response
            end
        end)
    end
}).start()

preloadAboutSupport()

local function showTextInputDialog(hint, callback)
    local inputLayout = LinearLayout(service)
    inputLayout.setOrientation(1)
    inputLayout.setPadding(40, 40, 40, 40)
    local title = TextView(service)
    title.setText(hint)
    title.setTextSize(16)
    title.setGravity(Gravity.CENTER)
    title.setPadding(0, 0, 0, 20)
    inputLayout.addView(title)
    local textBox = EditText(service)
    textBox.setHint("Type here...")
    textBox.setGravity(Gravity.TOP)
    textBox.setLayoutParams(LinearLayout.LayoutParams(-1, 200))
    inputLayout.addView(textBox)
    local btnLayout = LinearLayout(service)
    btnLayout.setOrientation(0)
    btnLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    local okBtn = Button(service)
    okBtn.setText("OK")
    okBtn.setBackgroundColor(0xFF2E7D32)
    okBtn.setTextColor(0xFFFFFFFF)
    local okParams = LinearLayout.LayoutParams(0, -2, 1)
    okParams.setMargins(0, 10, 5, 0)
    okBtn.setLayoutParams(okParams)
    btnLayout.addView(okBtn)
    local cancelBtn = Button(service)
    cancelBtn.setText("CANCEL")
    cancelBtn.setBackgroundColor(0xFF9E9E9E)
    cancelBtn.setTextColor(0xFFFFFFFF)
    local cancelParams = LinearLayout.LayoutParams(0, -2, 1)
    cancelParams.setMargins(5, 10, 0, 0)
    cancelBtn.setLayoutParams(cancelParams)
    btnLayout.addView(cancelBtn)
    inputLayout.addView(btnLayout)
    local inputDialog = AlertDialog.Builder(service)
    inputDialog.setTitle("Enter Text")
    inputDialog.setView(inputLayout)
    local dlg = inputDialog.create()
    dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    cancelBtn.onClick = function()
        dlg.dismiss()
    end
    okBtn.onClick = function()
        local text = textBox.getText().toString()
        dlg.dismiss()
        if text ~= "" then
            callback(text)
        end
    end
    dlg.show()
end

local scrollView = ScrollView(service)
scrollView.setLayoutParams(LinearLayout.LayoutParams(-1, -1))

local layout = LinearLayout(service)
layout.setOrientation(1)
layout.setPadding(40, 40, 40, 40)
layout.setBackgroundColor(0xFFFFFFFF)

local titleText = TextView(service)
titleText.setText("Auto Update Injector By Tech For V I")
titleText.setTextSize(20)
titleText.setGravity(Gravity.CENTER)
titleText.setTextColor(0xFF2E7D32)
layout.addView(titleText)

local devText = TextView(service)
devText.setText("Developer: Sabir Jamil")
devText.setTextSize(14)
devText.setGravity(Gravity.CENTER)
devText.setPadding(0, 0, 0, 20)
layout.addView(devText)

local row1 = LinearLayout(service)
row1.setOrientation(0)
row1.setLayoutParams(LinearLayout.LayoutParams(-1, -2))

local mainLuaEdit = EditText(service)
mainLuaEdit.setHint("Main Lua Direct Link...")
mainLuaEdit.setPadding(20, 20, 20, 20)
local editParams = LinearLayout.LayoutParams(0, -2, 1)
editParams.setMargins(0, 10, 5, 10)
mainLuaEdit.setLayoutParams(editParams)
row1.addView(mainLuaEdit)

local versionCheckEdit = EditText(service)
versionCheckEdit.setHint("Version Check Direct Link...")
versionCheckEdit.setPadding(20, 20, 20, 20)
versionCheckEdit.setLayoutParams(editParams)
row1.addView(versionCheckEdit)

local versionNumEdit = EditText(service)
versionNumEdit.setHint("Version Number (e.g. 1.0)")
versionNumEdit.setPadding(20, 20, 20, 20)
versionNumEdit.setLayoutParams(editParams)
row1.addView(versionNumEdit)

layout.addView(row1)

local row1_5 = LinearLayout(service)
row1_5.setOrientation(0)
row1_5.setLayoutParams(LinearLayout.LayoutParams(-1, -2))

local newFeaturesEdit = EditText(service)
newFeaturesEdit.setHint("New Features File Direct Link (Optional)")
newFeaturesEdit.setPadding(20, 20, 20, 20)
newFeaturesEdit.setLayoutParams(editParams)
row1_5.addView(newFeaturesEdit)

layout.addView(row1_5)

local row1_6 = LinearLayout(service)
row1_6.setOrientation(0)
row1_6.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
row1_6.setGravity(Gravity.CENTER_VERTICAL)

local soundLabel = TextView(service)
soundLabel.setText("Sound:")
soundLabel.setTextSize(13)
soundLabel.setTextColor(0xFF333333)
soundLabel.setPadding(5, 0, 10, 0)
row1_6.addView(soundLabel)

local soundSwitch = CheckBox(service)
soundSwitch.setText("")
soundSwitch.setChecked(true)
soundSwitch.setPadding(0, 10, 30, 10)
row1_6.addView(soundSwitch)

local vibrationLabel = TextView(service)
vibrationLabel.setText("Vibration:")
vibrationLabel.setTextSize(13)
vibrationLabel.setTextColor(0xFF333333)
vibrationLabel.setPadding(5, 0, 10, 0)
row1_6.addView(vibrationLabel)

local vibrationSwitch = CheckBox(service)
vibrationSwitch.setText("")
vibrationSwitch.setChecked(true)
vibrationSwitch.setPadding(0, 10, 0, 10)
row1_6.addView(vibrationSwitch)

layout.addView(row1_6)

local row2 = LinearLayout(service)
row2.setOrientation(0)
row2.setLayoutParams(LinearLayout.LayoutParams(-1, -2))

local typeSpinner = Spinner(service)
local typeAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, {"Extension", "Tool"})
typeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
typeSpinner.setAdapter(typeAdapter)
local spinnerParams = LinearLayout.LayoutParams(0, -2, 1)
spinnerParams.setMargins(0, 10, 5, 10)
typeSpinner.setLayoutParams(spinnerParams)
row2.addView(typeSpinner)

local statusSpinner = TextView(service)
statusSpinner.setText("Click to Select Folder...")
statusSpinner.setTextSize(16)
statusSpinner.setPadding(20, 20, 20, 20)
statusSpinner.setGravity(Gravity.CENTER_VERTICAL)
local gd = GradientDrawable()
gd.setColor(0xFFF0F0F0)
gd.setCornerRadius(10)
gd.setStroke(2, 0xFFCCCCCC)
statusSpinner.setBackgroundDrawable(gd)
statusSpinner.setLayoutParams(spinnerParams)
row2.addView(statusSpinner)

layout.addView(row2)

local selectedFolder = ""
local fullFolderList = {}

local function openFullSearchDialog(targetPath, typeName)
    local sLayout = LinearLayout(service)
    sLayout.setOrientation(1)
    sLayout.setPadding(30, 30, 30, 30)
    local searchEdit = EditText(service)
    searchEdit.setHint("Search " .. typeName .. "...")
    sLayout.addView(searchEdit)
    local lv = ListView(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, fullFolderList)
    lv.setAdapter(adapter)
    lv.setLayoutParams(LinearLayout.LayoutParams(-1, 0, 1))
    sLayout.addView(lv)
    local sDlg = AlertDialog.Builder(service).setTitle("Choose " .. typeName).setView(sLayout).setNegativeButton("GO BACK", nil).create()
    sDlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    searchEdit.addTextChangedListener(TextWatcher{onTextChanged=function(s) adapter.getFilter().filter(tostring(s)) end})
    lv.onItemClick = function(l, v, p, i)
        selectedFolder = tostring(v.Text)
        statusSpinner.setText("Current: " .. selectedFolder)
        sDlg.dismiss()
    end
    sDlg.show()
end

local function scanFolders(targetPath)
    fullFolderList = {}
    local folderObj = File(targetPath)
    if folderObj.exists() and folderObj.isDirectory() then
        local files = folderObj.listFiles()
        if files then
            for i = 0, #files - 1 do
                if files[i].isDirectory() then table.insert(fullFolderList, files[i].getName()) end
            end
        end
    end
    table.sort(fullFolderList)
    if #fullFolderList > 0 then
        statusSpinner.setText("Current: " .. fullFolderList[1])
        selectedFolder = fullFolderList[1]
    else
        statusSpinner.setText("Click to Select Folder...")
        selectedFolder = ""
    end
end

typeSpinner.onItemSelected = function(parent, view, position, id)
    scanFolders(parent.getItemAtPosition(position) == "Extension" and EXT_PATH or TOOL_PATH)
end

statusSpinner.onClick = function()
    openFullSearchDialog((typeSpinner.getSelectedItem() == "Extension" and EXT_PATH or TOOL_PATH), typeSpinner.getSelectedItem())
end

local row3 = LinearLayout(service)
row3.setOrientation(0)
row3.setLayoutParams(LinearLayout.LayoutParams(-1, -2))

local generateBtn = Button(service)
generateBtn.setText("GENERATE AUTO UPDATE")
generateBtn.setBackgroundColor(0xFF2E7D32)
generateBtn.setTextColor(0xFFFFFFFF)
local btnParams = LinearLayout.LayoutParams(0, -2, 1)
btnParams.setMargins(0, 10, 5, 10)
generateBtn.setLayoutParams(btnParams)
row3.addView(generateBtn)

local aboutBtn = Button(service)
aboutBtn.setText("ABOUT & SUPPORT")
aboutBtn.setBackgroundColor(0xFF2196F3)
aboutBtn.setTextColor(0xFFFFFFFF)
aboutBtn.setLayoutParams(btnParams)
row3.addView(aboutBtn)

local exitBtn = Button(service)
exitBtn.setText("EXIT")
exitBtn.setBackgroundColor(0xFF9E9E9E)
exitBtn.setTextColor(0xFFFFFFFF)
exitBtn.setLayoutParams(btnParams)
row3.addView(exitBtn)

layout.addView(row3)

scrollView.addView(layout)

_G.mainDlg = AlertDialog.Builder(service).setView(scrollView).create()
_G.mainDlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
_G.mainDialog = _G.mainDlg
_G.mainDlg.show()

local function generateAutoUpdate()
    if selectedFolder == "" then
        showMsg("Error: Select folder first!")
        return
    end
    
    local userMainLink = tostring(mainLuaEdit.getText())
    local userVersionLink = tostring(versionCheckEdit.getText())
    local userVersionNum = tostring(versionNumEdit.getText())
    local userNewFeaturesLink = tostring(newFeaturesEdit.getText())
    
    if userMainLink == "" or userMainLink == "nil" or userVersionLink == "" or userVersionNum == "" then
        showMsg("Error: All required fields are required! (Main Lua Link, Version Check Link, Version Number)")
        return
    end
    
    local convertedMainLink = convertToRawUrl(userMainLink)
    local convertedVersionLink = convertToRawUrl(userVersionLink)
    local convertedNewFeaturesLink = ""
    if userNewFeaturesLink ~= "" and userNewFeaturesLink ~= "nil" then
        convertedNewFeaturesLink = convertToRawUrl(userNewFeaturesLink)
    end
    
    local soundEnabled = soundSwitch.isChecked()
    local vibrationEnabled = vibrationSwitch.isChecked()
    
    local category = typeSpinner.getSelectedItem()
    local folderPath = (category == "Extension" and EXT_PATH or TOOL_PATH) .. selectedFolder
    local mainFilePath = folderPath .. "/main.lua"
    local oldFilePath = folderPath .. "/old_main.lua"
    local versionFilePath = folderPath .. "/version.txt"
    
    local mainFile = File(mainFilePath)
    local oldFile = File(oldFilePath)
    
    if not mainFile.exists() then
        showMsg("Error: main.lua not found!")
        return
    end

    if not oldFile.exists() then
        if not mainFile.renameTo(oldFile) then
            showMsg("Error: Could not create backup!")
            return
        end
    end

    local vf = io.open(versionFilePath, "w")
    if vf then
        vf:write(userVersionNum)
        vf:close()
    end

    local notificationFunc = ""
    if soundEnabled and vibrationEnabled then
        notificationFunc = [[
local function playNotification()
    local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
    tone.startTone(ToneGenerator.TONE_PROP_ACK, 100)
    local vibrator = (service or activity).getSystemService(Context.VIBRATOR_SERVICE)
    if vibrator then
        if Build.VERSION.SDK_INT >= 26 then
            vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
        else
            vibrator.vibrate(200)
        end
    end
end
]]
    elseif soundEnabled then
        notificationFunc = [[
local function playNotification()
    local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
    tone.startTone(ToneGenerator.TONE_PROP_ACK, 100)
end
]]
    elseif vibrationEnabled then
        notificationFunc = [[
local function playNotification()
    local vibrator = (service or activity).getSystemService(Context.VIBRATOR_SERVICE)
    if vibrator then
        if Build.VERSION.SDK_INT >= 26 then
            vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
        else
            vibrator.vibrate(200)
        end
    end
end
]]
    else
        notificationFunc = [[
local function playNotification()
    -- Notifications disabled by user
end
]]
    end

    local autoUpdateCode = [[
require "import"
import "android.*"
import "com.androlua.Http"
import "android.widget.Toast"
import "android.app.AlertDialog"
import "android.view.WindowManager"
import "android.os.Handler"
import "android.os.Looper"
import "java.io.File"
import "android.content.Context"
import "android.media.ToneGenerator"
import "android.media.AudioManager"
import "android.os.Vibrator"
import "android.os.Build"
import "android.os.VibrationEffect"
import "java.lang.Thread"

local updateURL = "]] .. convertedVersionLink .. [["
local downloadURL = "]] .. convertedMainLink .. [["
local newFeaturesURL = "]] .. convertedNewFeaturesLink .. [["
local defaultVersion = "]] .. userVersionNum .. [["
local currentDir = "]] .. folderPath .. [["
local oldPath = currentDir .. "/old_main.lua"
local mainPath = currentDir .. "/main.lua"
local versionPath = currentDir .. "/version.txt"

local updateInProgress = false
local prefs = (service or activity).getApplicationContext().getSharedPreferences("AutoUpdatePrefs", Context.MODE_PRIVATE)

]] .. notificationFunc .. [[

local function trim(s)
    if s == nil then return "" end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

local function getCurrentVersion()
    local f = io.open(versionPath, "r")
    if f then
        local ver = f:read("*a")
        f:close()
        if ver then return trim(ver) end
    end
    return defaultVersion
end

local function runOriginalCode()
    if File(oldPath).exists() then
        local func, err = loadfile(oldPath)
        if func then 
            pcall(func)
        end
    end
end

local function restartPlugin()
    pcall(function() service.execute("closeAllDialogs") end)
    pcall(function() service.toHome() end)

    package.loaded["main"] = nil 
    
    local currentFile = mainPath
    if File(currentFile).exists() then
        local func, err = loadfile(currentFile)
        if func then
            pcall(func)
        else
            Toast.makeText(service, "Load Error: " .. tostring(err), 0).show()
        end
    end
end

local function showNewFeaturesDialog(featuresText)
    Handler(Looper.getMainLooper()).post(Runnable{
        run=function()
            playNotification()
            
            local featuresDialog = AlertDialog.Builder(service or activity)
            featuresDialog.setTitle("New Update Details")
            featuresDialog.setMessage(featuresText or "No new features information available.")
            featuresDialog.setPositiveButton("OK", {onClick=function(v) v.dismiss() end})
            local dlg = featuresDialog.create()
            dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dlg.setCancelable(false)
            dlg.show()
        end
    })
end

-- FIXED: New checkAndShowNewFeatures function with proper Thread and timing
local function checkAndShowNewFeatures(versionToCheck)
    if newFeaturesURL == "" or newFeaturesURL == "nil" then return end
    
    -- Use Thread to avoid UI hang
    Thread(Runnable{
        run = function()
            local canShow = prefs.getBoolean("canShowFeatures", false)
            
            -- If flag is true, load features
            if canShow then
                Http.get(newFeaturesURL, function(code, content)
                    if code == 200 and content and trim(content) ~= "" then
                        Handler(Looper.getMainLooper()).post(Runnable{
                            run = function()
                                showNewFeaturesDialog(content)
                            end
                        })
                    end
                    -- Reset flag after showing dialog or if file not found
                    prefs.edit().putBoolean("canShowFeatures", false).putString("lastShownVersion", versionToCheck).apply()
                end)
            end
        end
    }).start()
end

local function performUpdate(onlineVersion)
    if updateInProgress then
        Toast.makeText(service, "Update already in progress...", 0).show()
        return
    end
    
    updateInProgress = true
    Toast.makeText(service, "Downloading update...", 0).show()
    
    Http.get(downloadURL, function(code, content)
        if code == 200 and content then
            local f = io.open(mainPath, "w")
            if f then
                f:write(content)
                f:close()
                
                local vf = io.open(versionPath, "w")
                if vf then
                    vf:write(onlineVersion)
                    vf:close()
                end
                
                updateInProgress = false
                
                -- FIXED: Better pref settings for features dialog
                prefs.edit()
                    .putBoolean("canShowFeatures", true)
                    .putString("lastShownVersion", "")
                    .apply()
                
                Handler(Looper.getMainLooper()).post(Runnable{run=function()
                    playNotification()
                    
                    local successDialog = AlertDialog.Builder(service or activity)
                    successDialog.setTitle("Update Successful")
                    successDialog.setMessage("Plugin updated to version " .. onlineVersion .. ".\n\nPlugin will restart automatically.")
                    successDialog.setPositiveButton("OK", {onClick=function(v)
                        v.dismiss()
                        
                        if _G.mainDlg then
                            _G.mainDlg.hide()
                        end
                        
                        Handler(Looper.getMainLooper()).postDelayed(Runnable{
                            run = function()
                                restartPlugin()
                            end
                        }, 500)
                    end})
                    local d2 = successDialog.create()
                    d2.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    d2.setCancelable(false)
                    d2.show()
                end})
            else
                updateInProgress = false
                Toast.makeText(service, "Failed to write update", 0).show()
            end
        else
            updateInProgress = false
            Toast.makeText(service, "Failed to download update", 0).show()
        end
    end)
end

local function checkUpdate()
    Http.get(updateURL, function(code, response)
        if code == 200 and response then
            local onlineVersion = trim(response)
            local currentVersion = getCurrentVersion()
            
            if onlineVersion ~= currentVersion then
                Handler(Looper.getMainLooper()).post(Runnable{run=function()
                    playNotification()
                    
                    if _G.mainDlg then
                        _G.mainDlg.dismiss()
                    end
                    
                    local updateAlertDlg = AlertDialog.Builder(service or activity)
                    updateAlertDlg.setTitle("Update Available")
                    updateAlertDlg.setMessage("New Version: " .. onlineVersion .. "\nCurrent: " .. currentVersion)
                    updateAlertDlg.setPositiveButton("Update Now", {onClick=function(v)
                        v.dismiss()
                        performUpdate(onlineVersion)
                    end})
                    updateAlertDlg.setNegativeButton("Later", {onClick=function(v)
                        v.dismiss()
                        if _G.mainDlg then
                            _G.mainDlg.show()
                        end
                    end})
                    
                    local d1 = updateAlertDlg.create()
                    d1.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    d1.setCancelable(false)
                    d1.show()
                end})
            end
        end
    end)
end

runOriginalCode()

-- FIXED: Proper timing with delays to ensure synchronization
-- Give main code time to load first
Handler(Looper.getMainLooper()).postDelayed(Runnable{
    run = function()
        checkAndShowNewFeatures(getCurrentVersion())
    end
}, 2000) -- 2 seconds delay is sufficient

Handler(Looper.getMainLooper()).postDelayed(Runnable{
    run = function()
        checkUpdate()
    end
}, 4000) -- Check update a bit later
]]

    local f = io.open(mainFilePath, "w")
    if f then
        f:write(autoUpdateCode)
        f:close()
        
        local settingsSummary = ""
        if soundEnabled and vibrationEnabled then
            settingsSummary = "Sound + Vibration"
        elseif soundEnabled then
            settingsSummary = "Sound Only"
        elseif vibrationEnabled then
            settingsSummary = "Vibration Only"
        else
            settingsSummary = "Disabled"
        end
        
        local newFeaturesStatus = (userNewFeaturesLink ~= "" and "Added" or "Not provided (Optional)")
        
        local successDialog = AlertDialog.Builder(service)
        successDialog.setTitle("Generate Successfully")
        successDialog.setMessage("Auto Update Injector Professional\n\n- Update injected into: " .. category .. "/" .. selectedFolder .. "\n- Notification Settings: " .. settingsSummary .. "\n- New Features Link: " .. newFeaturesStatus)
        successDialog.setPositiveButton("OK", function(v)
            v.dismiss()
        end)
        local dlg = successDialog.create()
        dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        dlg.show()
    else
        showMsg("Error: Failed to write file.")
    end
end

aboutBtn.onClick = createServerButtonHandler("About & Support")

generateBtn.onClick = function()
    generateAutoUpdate()
end

exitBtn.onClick = function() 
    if _G.mainDlg then
        _G.mainDlg.dismiss()
    end
end