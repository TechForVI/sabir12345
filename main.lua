require "import"
import "cjson"
import "android.widget.*"
import "android.os.*"
import "android.view.*"
import "android.content.Context"
import "android.graphics.Color"
import "android.content.Intent"
import "android.net.Uri"
import "android.provider.MediaStore"
import "java.io.File"
import "android.text.InputType"
import "android.widget.LinearLayout$LayoutParams"
import "android.graphics.Typeface"
import "java.net.URLEncoder"
import "java.lang.System"
import "com.androlua.Http"
import "android.graphics.Bitmap"
import "android.graphics.BitmapFactory"
import "android.util.Base64"
import "java.io.ByteArrayOutputStream"
import "android.graphics.Rect"
import "android.view.accessibility.AccessibilityNodeInfo"

-- Service mode
local ctx = service
local File_CLASS = luajava.bindClass("java.io.File")

-- ==================== IMAGE RECOGNIZER PRO CONFIG ====================
local AI_PREFS = "ImageRecognizerProAI"
local aiPrefs = ctx.getSharedPreferences(AI_PREFS, Context.MODE_PRIVATE)
local aiEditor = aiPrefs.edit()

local GEMINI_MODELS = {
    "Gemini 2.5 Flash",
    "Gemini 2.5 Pro",
    "Gemini 2.0 Flash"
}

local geminiApiDetails = {
    ["Gemini 2.5 Flash"] = { id = "models/gemini-2.5-flash", version = "v1beta" },
    ["Gemini 2.5 Pro"] = { id = "models/gemini-2.5-pro", version = "v1beta" },
    ["Gemini 2.0 Flash"] = { id = "models/gemini-2.0-flash", version = "v1beta" }
}

local POPULAR_LANGUAGES = {
    "English", "Urdu (اردو)", "Hindi (हिन्दी)", "Arabic (العربية)", 
    "Punjabi (پنجابی)", "Pashto (پشتو)", "Sindhi (سنڌي)", "Persian (فارسی)",
    "Spanish (Español)", "French (Français)", "German (Deutsch)", 
    "Chinese (中文)", "Russian (Русский)", "Japanese (日本語)", 
    "Turkish (Türkçe)", "Bengali (বাংলা)", "Portuguese (Português)"
}

local RECOGNIZE_OPTIONS = {
    "Image Process",
    "Current Screen",
    "Current Item",
    "Extract Text Only"
}

local photoFilePaths = {}
local selectedPhotoPath = ""
local mainDlg = nil
local processButton = nil

function notify(msg)
  if service and service.speak then service.speak(msg) end
  Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
end

function vibrate()
    local vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE)
    if vibrator then vibrator.vibrate(35) end
end

-- ==================== PREFERENCES FUNCTIONS ====================
function getGeminiApiKey() return aiPrefs.getString("gemini_apiKey", "") end
function saveGeminiApiKey(key) aiEditor.putString("gemini_apiKey", key); aiEditor.commit() end
function getSelectedLanguage() return aiPrefs.getString("selected_language", "English") end
function saveSelectedLanguage(lang) aiEditor.putString("selected_language", lang); aiEditor.commit() end
function getGeminiModel() return aiPrefs.getString("gemini_model", "Gemini 2.5 Flash") end
function saveGeminiModel(model) aiEditor.putString("gemini_model", model); aiEditor.commit() end
function getSelectedRecognizeOption() return aiPrefs.getString("rec_option", "Image Process") end
function saveSelectedRecognizeOption(opt) aiEditor.putString("rec_option", opt); aiEditor.commit() end

-- ==================== GET CURRENT FOCUSED ITEM ====================
function getCurrentFocusedItem()
    local focusedNode = nil
    
    -- Try multiple methods to get focused node
    if service.getFocusView then
        local success, result = pcall(function() return service.getFocusView() end)
        if success and result then
            focusedNode = result
        end
    end
    
    if not focusedNode and service.getCurrentNode then
        local success, result = pcall(function() return service.getCurrentNode() end)
        if success and result then
            focusedNode = result
        end
    end
    
    if not focusedNode and service.findFocus then
        local success, result = pcall(function() return service.findFocus() end)
        if success and result then
            focusedNode = result
        end
    end
    
    if not focusedNode and service.getRootInActiveWindow then
        local success, root = pcall(function() return service.getRootInActiveWindow() end)
        if success and root then
            focusedNode = findFocusedNodeInTree(root)
        end
    end
    
    return focusedNode
end

function findFocusedNodeInTree(node)
    if not node then return nil end
    
    local isFocused = false
    pcall(function() isFocused = node.isFocused() end)
    if isFocused then return node end
    
    local childCount = 0
    pcall(function() childCount = node.getChildCount() end)
    
    for i = 0, childCount - 1 do
        local child = nil
        pcall(function() child = node.getChild(i) end)
        if child then
            local result = findFocusedNodeInTree(child)
            if result then return result end
        end
    end
    
    return nil
end

-- ==================== GET ITEM INFORMATION ====================
function getItemDetails(node)
    if not node then return nil end
    
    local details = {}
    
    -- Get text
    pcall(function()
        local text = node.getText()
        if text and tostring(text) ~= "null" and tostring(text) ~= "" then
            details.text = tostring(text)
        end
    end)
    
    -- Get content description
    pcall(function()
        local desc = node.getContentDescription()
        if desc and tostring(desc) ~= "null" and tostring(desc) ~= "" then
            details.contentDescription = tostring(desc)
        end
    end)
    
    -- Get class name
    pcall(function()
        local className = node.getClassName()
        if className then
            local classStr = tostring(className)
            details.className = classStr
            -- Extract simple name
            local simpleName = classStr:match("%.(%w+)$") or classStr
            details.simpleType = simpleName
        end
    end)
    
    -- Get view ID
    pcall(function()
        local viewId = node.getViewIdResourceName()
        if viewId and tostring(viewId) ~= "null" and tostring(viewId) ~= "" then
            details.viewId = tostring(viewId)
        end
    end)
    
    -- Check if clickable
    pcall(function()
        details.isClickable = node.isClickable()
    end)
    
    -- Check if checkable
    pcall(function()
        details.isCheckable = node.isCheckable()
    end)
    
    -- Check if checked
    pcall(function()
        details.isChecked = node.isChecked()
    end)
    
    -- Check if enabled
    pcall(function()
        details.isEnabled = node.isEnabled()
    end)
    
    -- Get bounds
    pcall(function()
        local rect = Rect()
        node.getBoundsInScreen(rect)
        if rect.right > rect.left and rect.bottom > rect.top then
            details.bounds = {
                left = rect.left,
                top = rect.top,
                right = rect.right,
                bottom = rect.bottom,
                width = rect.right - rect.left,
                height = rect.bottom - rect.top
            }
        end
    end)
    
    return details
end

-- ==================== GENERATE ITEM DESCRIPTION ====================
function generateItemDescription(details)
    if not details then return "No item information available." end
    
    local description = {}
    
    -- Type identification
    if details.simpleType then
        if details.simpleType:find("Button") then
            table.insert(description, "This is a Button")
        elseif details.simpleType:find("Image") then
            table.insert(description, "This is an Icon/Image")
        elseif details.simpleType:find("Text") then
            table.insert(description, "This is a Text element")
        elseif details.simpleType:find("Check") then
            table.insert(description, "This is a Checkbox")
        elseif details.simpleType:find("Switch") then
            table.insert(description, "This is a Switch")
        elseif details.simpleType:find("Edit") then
            table.insert(description, "This is an Input Field")
        else
            table.insert(description, "This is a " .. details.simpleType)
        end
    else
        table.insert(description, "This is a UI Element")
    end
    
    -- Text content
    if details.text and details.text ~= "" then
        table.insert(description, "Text: \"" .. details.text .. "\"")
    end
    
    -- Content description
    if details.contentDescription and details.contentDescription ~= "" then
        table.insert(description, "Description: \"" .. details.contentDescription .. "\"")
    end
    
    -- View ID (often indicates what the icon is)
    if details.viewId and details.viewId ~= "" then
        local idName = details.viewId:match("/([^/]+)$") or details.viewId
        table.insert(description, "Element ID: " .. idName)
    end
    
    -- Clickable status
    if details.isClickable then
        table.insert(description, "This element can be clicked/tapped")
    else
        table.insert(description, "This element is not clickable")
    end
    
    -- Check state
    if details.isCheckable then
        if details.isChecked then
            table.insert(description, "This is checked/selected")
        else
            table.insert(description, "This is not checked")
        end
    end
    
    -- Size information
    if details.bounds then
        table.insert(description, "Size: " .. details.bounds.width .. "x" .. details.bounds.height .. " pixels")
    end
    
    return table.concat(description, "\n")
end

-- ==================== ANALYZE CURRENT ITEM ====================
function analyzeCurrentItem()
    -- Wait for focus to stabilize
    Thread.sleep(300)
    
    -- Get focused node
    local focusedNode = getCurrentFocusedItem()
    
    if not focusedNode then
        return "No item focused.\n\nPlease focus on any icon or element first by moving to it using your screen reader, then try again."
    end
    
    -- Get item details
    local details = getItemDetails(focusedNode)
    
    if not details then
        return "Could not get item information. Please try focusing on a different element."
    end
    
    -- Check if we have meaningful information
    local hasInfo = (details.text and details.text ~= "") or 
                    (details.contentDescription and details.contentDescription ~= "") or
                    (details.viewId and details.viewId ~= "")
    
    if not hasInfo then
        return "Item information:\n\n" ..
               "Type: " .. (details.simpleType or "Unknown") .. "\n" ..
               "Clickable: " .. (details.isClickable and "Yes" or "No") .. "\n\n" ..
               "This element has no text label or description. It may be a pure visual icon."
    end
    
    local language = getSelectedLanguage()
    local itemDesc = generateItemDescription(details)
    
    -- For Current Item, we'll use the accessibility information directly
    -- No image capture needed since we have all the info from accessibility
    local resultText = ""
    
    -- Parse view ID to guess icon type if possible
    local iconHint = ""
    if details.viewId then
        local idLower = details.viewId:lower()
        if idLower:find("settings") then
            iconHint = "\n💡 This appears to be a Settings icon."
        elseif idLower:find("home") then
            iconHint = "\n💡 This appears to be a Home icon."
        elseif idLower:find("back") then
            iconHint = "\n💡 This appears to be a Back navigation icon."
        elseif idLower:find("share") then
            iconHint = "\n💡 This appears to be a Share icon."
        elseif idLower:find("like") or idLower:find("thumbs") then
            iconHint = "\n💡 This appears to be a Like button."
        elseif idLower:find("comment") then
            iconHint = "\n💡 This appears to be a Comment icon."
        elseif idLower:find("search") then
            iconHint = "\n💡 This appears to be a Search icon."
        elseif idLower:find("menu") or idLower:find("hamburger") then
            iconHint = "\n💡 This appears to be a Menu icon."
        elseif idLower:find("camera") then
            iconHint = "\n💡 This appears to be a Camera icon."
        elseif idLower:find("mic") or idLower:find("microphone") then
            iconHint = "\n💡 This appears to be a Microphone icon."
        elseif idLower:find("send") then
            iconHint = "\n💡 This appears to be a Send icon."
        elseif idLower:find("attach") or idLower:find("clip") then
            iconHint = "\n💡 This appears to be an Attach file icon."
        end
    end
    
    -- Build analysis based on available information
    resultText = "📱 **Current Item Analysis**\n\n"
    resultText = resultText .. "**What is this element?**\n"
    
    -- Determine element type
    if details.simpleType then
        if details.simpleType:find("Button") then
            resultText = resultText .. "• Type: Button\n"
        elseif details.simpleType:find("Image") then
            resultText = resultText .. "• Type: Icon / Image Button\n"
        elseif details.simpleType:find("Text") then
            resultText = resultText .. "• Type: Text Label\n"
        elseif details.simpleType:find("Check") then
            resultText = resultText .. "• Type: Checkbox\n"
        elseif details.simpleType:find("Switch") then
            resultText = resultText .. "• Type: Toggle Switch\n"
        else
            resultText = resultText .. "• Type: " .. details.simpleType .. "\n"
        end
    end
    
    -- Add text/description
    if details.text and details.text ~= "" then
        resultText = resultText .. "• Label: \"" .. details.text .. "\"\n"
    end
    if details.contentDescription and details.contentDescription ~= "" then
        resultText = resultText .. "• Description: \"" .. details.contentDescription .. "\"\n"
    end
    
    -- Add clickable info
    if details.isClickable then
        resultText = resultText .. "• Action: Clickable - triggers an action when tapped\n"
    end
    
    resultText = resultText .. "\n**What app does this belong to?**\n"
    
    -- Try to guess app from view ID or context
    if details.viewId then
        if details.viewId:find("whatsapp") or details.viewId:find("wa_") then
            resultText = resultText .. "• This appears to be from **WhatsApp**\n"
        elseif details.viewId:find("telegram") then
            resultText = resultText .. "• This appears to be from **Telegram**\n"
        elseif details.viewId:find("gmail") or details.viewId:find("google") then
            resultText = resultText .. "• This appears to be from **Google/Gmail**\n"
        elseif details.viewId:find("youtube") then
            resultText = resultText .. "• This appears to be from **YouTube**\n"
        elseif details.viewId:find("instagram") then
            resultText = resultText .. "• This appears to be from **Instagram**\n"
        elseif details.viewId:find("facebook") then
            resultText = resultText .. "• This appears to be from **Facebook**\n"
        else
            resultText = resultText .. "• App could not be determined from element ID\n"
        end
    else
        resultText = resultText .. "• App could not be determined\n"
    end
    
    resultText = resultText .. "\n**What does this element do?**\n"
    
    -- Determine function based on ID and text
    local functionText = ""
    if details.viewId then
        local idLower = details.viewId:lower()
        if idLower:find("settings") then
            functionText = "Opens settings/preferences menu"
        elseif idLower:find("home") then
            functionText = "Navigates to home screen"
        elseif idLower:find("back") then
            functionText = "Goes back to previous screen"
        elseif idLower:find("share") then
            functionText = "Shares content with others"
        elseif idLower:find("like") then
            functionText = "Likes/favorites the content"
        elseif idLower:find("comment") then
            functionText = "Opens comments section"
        elseif idLower:find("search") then
            functionText = "Opens search interface"
        elseif idLower:find("menu") then
            functionText = "Opens navigation menu"
        elseif idLower:find("camera") then
            functionText = "Opens camera to take photo"
        elseif idLower:find("mic") then
            functionText = "Starts voice input/recording"
        elseif idLower:find("send") then
            functionText = "Sends message or content"
        elseif idLower:find("attach") then
            functionText = "Attaches file or media"
        elseif idLower:find("delete") or idLower:find("trash") then
            functionText = "Deletes the item"
        elseif idLower:find("edit") then
            functionText = "Edits the content"
        elseif idLower:find("add") or idLower:find("plus") then
            functionText = "Adds new item"
        else
            functionText = "Triggers its associated action when tapped"
        end
    else
        functionText = "Triggers its associated action when tapped"
    end
    
    resultText = resultText .. "• " .. functionText .. "\n"
    
    resultText = resultText .. "\n**Summary:**\n"
    if details.text and details.text ~= "" then
        resultText = resultText .. "• This is a " .. (details.simpleType or "UI element") .. " labeled \"" .. details.text .. "\""
    elseif details.contentDescription and details.contentDescription ~= "" then
        resultText = resultText .. "• This is a " .. (details.simpleType or "UI element") .. " for \"" .. details.contentDescription .. "\""
    else
        resultText = resultText .. "• This is a " .. (details.simpleType or "visual icon") .. " " .. functionText:lower()
    end
    resultText = resultText .. ".\n"
    
    if iconHint ~= "" then
        resultText = resultText .. iconHint .. "\n"
    end
    
    return resultText
end

-- ==================== ANALYZE CURRENT SCREEN ====================
function analyzeCurrentScreen()
    return "📱 **Current Screen Analysis**\n\n" ..
           "To analyze the current screen, please use this feature with an image.\n" ..
           "The Current Item mode analyzes the focused element using accessibility information.\n\n" ..
           "**How to use Current Item:**\n" ..
           "1. Navigate to any icon or button using your screen reader\n" ..
           "2. Make sure the element is focused (highlighted)\n" ..
           "3. Select 'Current Item' from the dropdown\n" ..
           "4. Click Process\n\n" ..
           "The plugin will identify the icon and explain its function."
end

-- ==================== IMAGE TO BASE64 ====================
function pathToBase64(imagePath)
    if not imagePath or imagePath == "" then return nil end
    local imgFile = File_CLASS(imagePath)
    if not imgFile.exists() or not imgFile.canRead() then return nil end
    local options = BitmapFactory.Options()
    options.inSampleSize = 2
    local bitmap = BitmapFactory.decodeFile(imagePath, options)
    if not bitmap then return nil end
    local outputStream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 80, outputStream)
    local imageBytes = outputStream.toByteArray()
    outputStream.close()
    bitmap.recycle()
    return Base64.encodeToString(imageBytes, Base64.NO_WRAP)
end

-- ==================== GEMINI API CALL ====================
function callGeminiWithImage(apiKey, model, base64Data, prompt, callback)
    local modelInfo = geminiApiDetails[model]
    local url = "https://generativelanguage.googleapis.com/" .. modelInfo.version .. "/" .. modelInfo.id .. ":generateContent?key=" .. apiKey
    local payload = {
        contents = {{
            parts = {
                { text = prompt },
                { inlineData = { mimeType = "image/jpeg", data = base64Data } }
            }
        }}
    }
    
    Http.post(url, cjson.encode(payload), { ["Content-Type"] = "application/json" }, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.candidates and decoded.candidates[1] then
                local result = decoded.candidates[1].content.parts[1].text
                callback(result, nil)
            else
                callback(nil, "Invalid API response")
            end
        else
            callback(nil, "Error: " .. status)
        end
    end)
end

-- ==================== ANALYZE IMAGE WITH GEMINI ====================
function analyzeWithGemini(base64Data, prompt)
    local apiKey = getGeminiApiKey()
    if not apiKey or apiKey == "" then
        return "API Key missing! Please set in Settings."
    end
    
    local resultText = ""
    local completed = false
    
    callGeminiWithImage(apiKey, getGeminiModel(), base64Data, prompt, function(res, err)
        completed = true
        if res then
            resultText = res
        else
            resultText = "Error: " .. (err or "Unknown error")
        end
    end)
    
    local waitTime = 0
    while not completed and waitTime < 30000 do
        Thread.sleep(100)
        waitTime = waitTime + 100
    end
    
    return resultText
end

-- ==================== IMAGE SELECTION ====================
function scanAllImages()
    notify("Scanning images...")
    local foundFiles = {}
    local contentResolver = ctx.getContentResolver()
    local uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    local projection = { MediaStore.Images.Media.DATA, MediaStore.Images.Media.DISPLAY_NAME }
    local cursor = contentResolver.query(uri, projection, nil, nil, MediaStore.Images.Media.DATE_ADDED .. " DESC")
    
    if cursor ~= nil then
        local dataCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
        local nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
        while cursor.moveToNext() do
            local path = cursor.getString(dataCol)
            local name = cursor.getString(nameCol)
            if path and name then
                table.insert(foundFiles, {path = path, name = name})
            end
        end
        cursor.close()
    end
    
    if #foundFiles > 0 then
        local adapterData = {}
        photoFilePaths = {}
        for _, file in ipairs(foundFiles) do
            table.insert(adapterData, file.name)
            table.insert(photoFilePaths, file.path)
        end
        
        local listLayout = LinearLayout(ctx)
        listLayout.setOrientation(1)
        local listView = ListView(ctx)
        listView.setAdapter(ArrayAdapter(ctx, android.R.layout.simple_list_item_1, adapterData))
        listLayout.addView(listView)
        
        local listDlg = LuaDialog(ctx)
        listDlg.setTitle("Select Image")
        listDlg.setView(listLayout)
        listDlg.show()
        
        listView.setOnItemClickListener(AdapterView.OnItemClickListener{
            onItemClick = function(p, v, pos, id)
                selectedPhotoPath = photoFilePaths[pos + 1]
                if _G.statusLabel then
                    _G.statusLabel.setText("Selected: " .. File_CLASS(selectedPhotoPath).getName())
                end
                notify("Selected: " .. File_CLASS(selectedPhotoPath).getName())
                listDlg.dismiss()
            end
        })
    else
        notify("No images found.")
    end
end

-- ==================== SETTINGS DIALOG ====================
function showAISettingsDialog()
    local settingsLayout = LinearLayout(ctx)
    settingsLayout.setOrientation(1)
    settingsLayout.setPadding(40, 20, 40, 20)
    
    local apiLabel = TextView(ctx)
    apiLabel.setText("Gemini API Key:")
    settingsLayout.addView(apiLabel)
    
    local apiInput = EditText(ctx)
    apiInput.setHint("Enter your API key")
    apiInput.setText(getGeminiApiKey())
    apiInput.setInputType(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
    settingsLayout.addView(apiInput)
    
    local modelLabel = TextView(ctx)
    modelLabel.setText("Select Model:")
    modelLabel.setPadding(0, 20, 0, 0)
    settingsLayout.addView(modelLabel)
    
    local modelSpinner = Spinner(ctx)
    local modelAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, GEMINI_MODELS)
    modelSpinner.setAdapter(modelAdapter)
    local savedModel = getGeminiModel()
    for i = 1, #GEMINI_MODELS do
        if GEMINI_MODELS[i] == savedModel then
            modelSpinner.setSelection(i - 1)
            break
        end
    end
    settingsLayout.addView(modelSpinner)
    
    local infoText = TextView(ctx)
    infoText.setText("Get API key from: makersuite.google.com/app/apikey")
    infoText.setTextSize(11)
    infoText.setTextColor(0xFF888888)
    infoText.setPadding(0, 20, 0, 0)
    settingsLayout.addView(infoText)
    
    local settingsDlg = LuaDialog(ctx)
    settingsDlg.setTitle("AI Engine Settings")
    settingsDlg.setView(settingsLayout)
    settingsDlg.setPositiveButton("Save", function()
        local newKey = apiInput.getText().toString()
        if newKey ~= "" then
            saveGeminiApiKey(newKey)
        end
        saveGeminiModel(GEMINI_MODELS[modelSpinner.getSelectedItemPosition() + 1])
        notify("Settings saved")
        settingsDlg.dismiss()
    end)
    settingsDlg.setNegativeButton("Cancel", nil)
    settingsDlg.show()
end

-- ==================== ABOUT AND SUPPORT ====================
function aboutAndSupport()
    vibrate()
    
    local help_views = {}
    local help_layout = {
        LinearLayout;
        orientation = "vertical";
        padding = "16dp";
        layout_width = "fill";
        layout_height = "wrap";
        {
            TextView;
            text = "Image Recognizer Pro provides AI-powered image recognition using Google Gemini AI.\n\nFeatures:\n• 4 recognition modes (Image Process, Current Screen, Current Item, Extract Text Only)\n• Multi-language support (18+ languages)\n• Google Gemini AI integration\n• Current item/screen recognition using accessibility services\n\nJoin our community for more useful tools, feedback, and suggestions.";
            textSize = 14;
            textColor = "#666666";
            gravity = "left";
            paddingBottom = "20dp";
        };
        {
            TextView;
            text = "Join Our Community";
            textSize = 16;
            textColor = "#000000";
            gravity = "center";
            paddingBottom = "10dp";
        };
        {
            ScrollView;
            layout_width = "fill";
            layout_height = "wrap_content";
            {
                LinearLayout;
                orientation = "vertical";
                layout_width = "fill";
                layout_height = "wrap_content";
                gravity = "center";
                layout_marginTop = "5dp";
                {
                    Button;
                    id = "joinWhatsAppGroupButton";
                    text = "JOIN WHATSAPP GROUP";
                    layout_width = "fill";
                    layout_height = "wrap_content";
                    layout_margin = "2dp";
                    textSize = "12sp";
                    padding = "8dp";
                    backgroundColor = "#25D366";
                    textColor = "#FFFFFF";
                };
                {
                    Button;
                    id = "joinYouTubeChannelButton";
                    text = "JOIN YOUTUBE CHANNEL";
                    layout_width = "fill";
                    layout_height = "wrap_content";
                    layout_margin = "2dp";
                    textSize = "12sp";
                    padding = "8dp";
                    backgroundColor = "#FF0000";
                    textColor = "#FFFFFF";
                };
                {
                    Button;
                    id = "joinTelegramChannelButton";
                    text = "JOIN TELEGRAM CHANNEL";
                    layout_width = "fill";
                    layout_height = "wrap_content";
                    layout_margin = "2dp";
                    textSize = "12sp";
                    padding = "8dp";
                    backgroundColor = "#2196F3";
                    textColor = "#FFFFFF";
                };
                {
                    Button;
                    id = "goBackButton";
                    text = "GO BACK";
                    layout_width = "fill";
                    layout_height = "wrap_content";
                    layout_margin = "2dp";
                    textSize = "12sp";
                    padding = "8dp";
                    backgroundColor = "#9E9E9E";
                    textColor = "#FFFFFF";
                };
            };
        };
    }
    
    local help_dialog = LuaDialog(ctx)
    help_dialog.setTitle("Developer: Sabir Jamil")
    help_dialog.setView(loadlayout(help_layout, help_views))
    help_dialog.setCancelable(true)
    
    help_views.joinWhatsAppGroupButton.onClick = function()
        local function performActions()
            help_dialog.dismiss()
            if mainDlg then
                mainDlg.dismiss()
            end
            local success = pcall(function()
                local message = "Assalam%20o%20Alaikum.%20I%20hope%20you%20are%20doing%20well.%20I%20would%20like%20to%20join%20your%20WhatsApp%20group.%20Kindly%20share%20the%20instructions.%20group%20rules%20and%20regulations.%20Thank%20you.%20so%20much"
                local url = "https://wa.me/923486623399?text=" .. message
                local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                ctx.startActivity(intent)
            end)
            if not success then
                notify("Could not open WhatsApp")
            end
        end
        if service and service.speak then
            service.speak("Opening WhatsApp Group")
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({
                run = performActions
            }), 1000)
        else
            performActions()
        end
    end
    
    help_views.joinYouTubeChannelButton.onClick = function()
        local function performActions()
            help_dialog.dismiss()
            if mainDlg then
                mainDlg.dismiss()
            end
            local success = pcall(function()
                local url = "https://www.youtube.com/@TechForVI"
                local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                ctx.startActivity(intent)
            end)
            if not success then
                notify("Could not open YouTube")
            end
        end
        if service and service.speak then
            service.speak("Opening YouTube Channel")
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({
                run = performActions
            }), 1000)
        else
            performActions()
        end
    end
    
    help_views.joinTelegramChannelButton.onClick = function()
        local function performActions()
            help_dialog.dismiss()
            if mainDlg then
                mainDlg.dismiss()
            end
            local success = pcall(function()
                local url = "https://t.me/TechForVI"
                local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                intent.setPackage("org.telegram.messenger")
                ctx.startActivity(intent)
            end)
            if not success then
                pcall(function()
                    local url = "https://t.me/TechForVI"
                    local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    ctx.startActivity(intent)
                end)
            end
        end
        if service and service.speak then
            service.speak("Opening Telegram Channel")
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({
                run = performActions
            }), 1000)
        else
            performActions()
        end
    end
    
    help_views.goBackButton.onClick = function()
        help_dialog.dismiss()
    end
    
    help_dialog.setOnCancelListener{
        onCancel = function()
            help_dialog.dismiss()
        end
    }
    
    help_dialog.show()
end

-- ==================== MAIN UI ====================
function createMainUI()
    local layout = LinearLayout(ctx)
    layout.setOrientation(1)
    layout.setPadding(40, 40, 40, 40)
    
    local devLabel = TextView(ctx)
    devLabel.setText("Developer: Sabir Jamil")
    devLabel.setGravity(Gravity.CENTER)
    layout.addView(devLabel)
    
    local btnScan = Button(ctx)
    btnScan.setText("CHOOSE FROM GALLERY")
    btnScan.onClick = function() scanAllImages() end
    layout.addView(btnScan)
    
    _G.statusLabel = TextView(ctx)
    _G.statusLabel.setText("No file selected")
    _G.statusLabel.setPadding(0, 20, 0, 20)
    _G.statusLabel.setGravity(Gravity.CENTER)
    layout.addView(_G.statusLabel)
    
    -- Language Selection
    local langLabel = TextView(ctx)
    langLabel.setText("Select Output Language:")
    langLabel.setTextSize(13)
    layout.addView(langLabel)
    
    local langSpinner = Spinner(ctx)
    local langAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, POPULAR_LANGUAGES)
    langSpinner.setAdapter(langAdapter)
    local savedLang = getSelectedLanguage()
    for i = 1, #POPULAR_LANGUAGES do
        if POPULAR_LANGUAGES[i] == savedLang then
            langSpinner.setSelection(i - 1)
        end
    end
    langSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
        onItemSelected = function(p, v, pos, id)
            saveSelectedLanguage(POPULAR_LANGUAGES[pos + 1])
        end
    })
    layout.addView(langSpinner)
    
    -- Recognition Mode Spinner
    local recLabel = TextView(ctx)
    recLabel.setText("Recognition Mode:")
    recLabel.setTextSize(13)
    recLabel.setPadding(0, 15, 0, 0)
    layout.addView(recLabel)
    
    local recSpinner = Spinner(ctx)
    local recAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, RECOGNIZE_OPTIONS)
    recSpinner.setAdapter(recAdapter)
    local savedOpt = getSelectedRecognizeOption()
    for i = 1, #RECOGNIZE_OPTIONS do
        if RECOGNIZE_OPTIONS[i] == savedOpt then
            recSpinner.setSelection(i - 1)
        end
    end
    recSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
        onItemSelected = function(p, v, pos, id)
            saveSelectedRecognizeOption(RECOGNIZE_OPTIONS[pos + 1])
        end
    })
    layout.addView(recSpinner)
    
    -- Process Button
    processButton = Button(ctx)
    processButton.setText("Process")
    processButton.setBackgroundColor(0xFFFF9800)
    processButton.onClick = function()
        processButton.setEnabled(false)
        processButton.setText("Processing Please Wait...")
        processButton.setBackgroundColor(0xFF999999)
        
        local selectedOption = getSelectedRecognizeOption()
        
        if selectedOption == "Current Screen" then
            if mainDlg then 
                mainDlg.dismiss()
                mainDlg = nil
            end
            
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({
                run = function()
                    local result = analyzeCurrentScreen()
                    local resultDlg = LuaDialog(ctx)
                    resultDlg.setTitle("Screen Analysis")
                    local scrollView = ScrollView(ctx)
                    local textView = TextView(ctx)
                    textView.setText(result)
                    textView.setTextSize(14)
                    textView.setPadding(30, 20, 30, 20)
                    textView.setTextColor(0xFF000000)
                    scrollView.addView(textView)
                    resultDlg.setView(scrollView)
                    resultDlg.setPositiveButton("Close", nil)
                    resultDlg.setNeutralButton("Copy", function()
                        local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
                        clipboard.setText(result)
                        if service and service.speak then
                            service.speak("Copied to clipboard successfully")
                        end
                        Toast.makeText(ctx, "Copied to clipboard successfully", Toast.LENGTH_SHORT).show()
                        vibrate()
                    end)
                    resultDlg.show()
                    
                    processButton.setEnabled(true)
                    processButton.setText("Process")
                    processButton.setBackgroundColor(0xFFFF9800)
                end
            }), 500)
            
        elseif selectedOption == "Current Item" then
            if mainDlg then 
                mainDlg.dismiss()
                mainDlg = nil
            end
            
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({
                run = function()
                    local result = analyzeCurrentItem()
                    local resultDlg = LuaDialog(ctx)
                    resultDlg.setTitle("Item Analysis")
                    local scrollView = ScrollView(ctx)
                    local textView = TextView(ctx)
                    textView.setText(result)
                    textView.setTextSize(14)
                    textView.setPadding(30, 20, 30, 20)
                    textView.setTextColor(0xFF000000)
                    scrollView.addView(textView)
                    resultDlg.setView(scrollView)
                    resultDlg.setPositiveButton("Close", nil)
                    resultDlg.setNeutralButton("Copy", function()
                        local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
                        clipboard.setText(result)
                        if service and service.speak then
                            service.speak("Copied to clipboard successfully")
                        end
                        Toast.makeText(ctx, "Copied to clipboard successfully", Toast.LENGTH_SHORT).show()
                        vibrate()
                    end)
                    resultDlg.show()
                    
                    processButton.setEnabled(true)
                    processButton.setText("Process")
                    processButton.setBackgroundColor(0xFFFF9800)
                end
            }), 500)
            
        elseif selectedOption == "Image Process" or selectedOption == "Extract Text Only" then
            if selectedPhotoPath == "" then
                notify("Please select an image first")
                processButton.setEnabled(true)
                processButton.setText("Process")
                processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            local apiKey = getGeminiApiKey()
            if not apiKey or apiKey == "" then
                notify("API Key missing! Set in Settings")
                processButton.setEnabled(true)
                processButton.setText("Process")
                processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            
            local base64Data = pathToBase64(selectedPhotoPath)
            if not base64Data then
                notify("Failed to process image")
                processButton.setEnabled(true)
                processButton.setText("Process")
                processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            
            local prompt = ""
            if selectedOption == "Extract Text Only" then
                prompt = "Extract only the text from this image. Output the text exactly as seen."
            else
                prompt = "Analyze this image in detail. Describe what you see, including objects, people, text, colors, and context. Provide the response in " .. getSelectedLanguage()
            end
            
            notify("Processing with Gemini AI...")
            
            callGeminiWithImage(apiKey, getGeminiModel(), base64Data, prompt, function(res, err)
                local resultDlg = LuaDialog(ctx)
                resultDlg.setTitle("Result")
                
                local scrollView = ScrollView(ctx)
                local textView = TextView(ctx)
                local resultText = res or "Error: " .. (err or "Unknown")
                textView.setText(resultText)
                textView.setTextSize(14)
                textView.setPadding(30, 20, 30, 20)
                textView.setTextColor(0xFF000000)
                scrollView.addView(textView)
                resultDlg.setView(scrollView)
                
                resultDlg.setPositiveButton("Close", nil)
                resultDlg.setNeutralButton("Copy", function()
                    local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
                    clipboard.setText(resultText)
                    if service and service.speak then
                        service.speak("Copied to clipboard successfully")
                    end
                    Toast.makeText(ctx, "Copied to clipboard successfully", Toast.LENGTH_SHORT).show()
                    vibrate()
                end)
                resultDlg.show()
                vibrate()
                
                processButton.setEnabled(true)
                processButton.setText("Process")
                processButton.setBackgroundColor(0xFFFF9800)
            end)
        end
    end
    layout.addView(processButton)
    
    -- Bottom Buttons
    local bottomLayout = LinearLayout(ctx)
    bottomLayout.setOrientation(0)
    bottomLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    bottomLayout.setPadding(0, 20, 0, 0)
    
    local btnSettings = Button(ctx)
    btnSettings.setText("Settings")
    btnSettings.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnSettings.onClick = function() showAISettingsDialog() end
    bottomLayout.addView(btnSettings)
    
    local btnAbout = Button(ctx)
    btnAbout.setText("About & Support")
    btnAbout.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnAbout.onClick = function() aboutAndSupport() end
    bottomLayout.addView(btnAbout)
    
    local btnExit = Button(ctx)
    btnExit.setText("Exit")
    btnExit.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnExit.setBackgroundColor(0xFFF44336)
    btnExit.onClick = function()
        if mainDlg then
            mainDlg.dismiss()
            mainDlg = nil
        end
    end
    bottomLayout.addView(btnExit)
    
    layout.addView(bottomLayout)
    
    mainDlg = LuaDialog(ctx)
    mainDlg.setTitle("Image Recognizer Pro")
    mainDlg.setView(layout)
    mainDlg.show()
end

-- Start the plugin
createMainUI()