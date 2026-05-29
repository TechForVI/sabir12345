require "import"
import "android.widget.*"
import "android.view.*"
import "android.app.*"
import "android.content.*"
import "android.provider.MediaStore"
import "android.text.*"
import "android.graphics.Typeface"
import "android.view.Gravity"
import "android.media.MediaPlayer"
import "android.media.MediaExtractor"
import "android.media.MediaMuxer"
import "android.media.MediaFormat"
import "android.media.MediaCodec"
import "android.media.ToneGenerator"
import "android.media.AudioManager"
import "android.speech.tts.TextToSpeech"
import "java.nio.ByteBuffer"
import "java.io.File"
import "java.text.SimpleDateFormat"
import "java.util.Date"
import "java.util.Locale"
import "android.os.Handler"
import "android.os.Looper"
import "android.os.Vibrator"
import "java.lang.Thread"
import "java.lang.Runnable"
import "android.view.WindowManager"
import "android.net.Uri"
import "android.database.Cursor"
import "android.content.Intent"
import "cjson"

local ctx = service or activity
local selected_videos_list = {}
local current_video_index = 0
local selected_video_path = nil
local selected_video_name = nil
local selected_video_duration = nil
local selected_video_size = nil

local videoPreviewPlayer = MediaPlayer()
local uiHandler = Handler(Looper.getMainLooper())
local is_video_previewing = false
local is_playing = false
local tts = nil
local selectedVideoTitleTV = nil
local selectedVideoDurationTV = nil
local mainDialogInstance = nil
local selectDialogInstance = nil
local previewBtn = nil
local nextBtn = nil
local prevBtn = nil

-- ========== AUTO UPDATE VARIABLES ==========
local CURRENT_VERSION = "2.0"
local VERSION_URL = "https://video-to-audio-converter-nu.vercel.app/version"
local UPDATE_CODE_URL = "https://video-to-audio-converter-nu.vercel.app/main.lua"
local NEW_FEATURES_URL = "https://video-to-audio-converter-nu.vercel.app/new%20features"
local PLUGIN_PATH = "/storage/emulated/0/解说/Plugins/Video to Audio Converter/main.lua"
local updateInProgress = false

local prefs = ctx.getSharedPreferences("VideoToAudioConverterPrefs", Context.MODE_PRIVATE)
-- ===========================================

local showMainDialog
local showVideoSelectionDialog

tts = TextToSpeech(service, TextToSpeech.OnInitListener{
onInit = function(status)
if status == TextToSpeech.SUCCESS then 
tts.setLanguage(Locale.US) 
end
end
})

local function giveFeedback(success)
local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
tone.startTone(success and ToneGenerator.TONE_PROP_ACK or ToneGenerator.TONE_PROP_NACK)
local vibrator = service.getSystemService(Context.VIBRATOR_SERVICE)
if vibrator then vibrator.vibrate(500) end
end

local function beepAndVibrate()
    local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
    tone.startTone(ToneGenerator.TONE_PROP_ACK, 500)
    local vibrator = service.getSystemService(Context.VIBRATOR_SERVICE)
    if vibrator then vibrator.vibrate(500) end
end

local function speakTTS(text, delay)
if is_video_previewing then return end
local str = tostring(text)
uiHandler.postDelayed(Runnable{
run = function()
if not is_video_previewing then
if tts then tts.speak(str, TextToSpeech.QUEUE_FLUSH, nil) end
service.speak(str)
end
end
}, delay or 0)
end

local function setT(view, text)
if not view then return end
local str = tostring(text)
if tostring(view):find("ProgressDialog") then view.setMessage(str)
else view.setText(str) end
end

local function setH(view, text)
if view then view.setHint(tostring(text)) end
end

local function showSafe(builder)
local dl = builder.create()
dl.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
dl.show()
return dl
end

-- ========== AUTO UPDATE FUNCTIONS ==========
function trim(s)
    if s == nil then return "" end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

function showUpdateErrorDialog(title, message)
    Handler(Looper.getMainLooper()).post(Runnable{
        run=function()
            local errorDialog = LuaDialog(ctx)
            errorDialog.setTitle(title)
            errorDialog.setMessage(message)
            errorDialog.setButton("OK", function()
                errorDialog.dismiss()
            end)
            showSafe(errorDialog)
        end
    })
end

function showNewFeaturesDialog(featuresText)
    Handler(Looper.getMainLooper()).post(Runnable{
        run=function()
            beepAndVibrate()
            
            local featuresDialog = LuaDialog(ctx)
            featuresDialog.setTitle("New Update Details")
            local layout = {
                LinearLayout,
                orientation = "vertical",
                layout_width = "match_parent",
                layout_height = "match_parent",
                padding = "16dp",
                {
                    ScrollView,
                    layout_width = "match_parent",
                    layout_height = "0dp",
                    layout_weight = 1,
                    {
                        TextView,
                        text = featuresText or "No new features information available.",
                        textSize = "14sp",
                        padding = "10dp",
                        layout_width = "match_parent",
                        layout_height = "wrap_content",
                    },
                },
                {
                    Button,
                    text = "OK",
                    textSize = "16sp",
                    layout_width = "match_parent",
                    layout_height = "wrap_content",
                    layout_marginTop = "10dp",
                    onClick = function()
                        featuresDialog.dismiss()
                    end,
                },
            }
            featuresDialog.setView(loadlayout(layout))
            featuresDialog.setCancelable(false)
            showSafe(featuresDialog)
        end
    })
end

function checkAndShowNewFeatures()
    local lastShownVersion = prefs.getString("lastShownVersion", "")
    if lastShownVersion ~= CURRENT_VERSION then
        Http.get(NEW_FEATURES_URL, function(code, response)
            if code == 200 and response and trim(response) ~= "" then
                showNewFeaturesDialog(response)
                prefs.edit().putString("lastShownVersion", CURRENT_VERSION).apply()
            end
        end)
    end
end

function checkUpdate()
    if updateInProgress then
        showUpdateErrorDialog("Update In Progress", "An update is already in progress. Please wait.")
        return
    end
    Http.get(VERSION_URL, function(code, response)
        if code == 200 and response then
            local onlineVersion = trim(response)
            if onlineVersion ~= CURRENT_VERSION then
                Http.get(UPDATE_CODE_URL, function(code2, mainCode)
                    if code2 == 200 and mainCode and trim(mainCode) ~= "" then
                        Handler(Looper.getMainLooper()).post(Runnable{
                            run=function()
                                beepAndVibrate()
                                
                                local updateAlertDlg = LuaDialog(ctx)
                                updateAlertDlg.setTitle("Update Available!")
                                updateAlertDlg.setMessage("A new version (" .. onlineVersion .. ") is available.\n\nWould you like to update now?")
                                updateAlertDlg.setButton("Update Now", function()
                                    updateAlertDlg.dismiss()
                                    performUpdate(mainCode, onlineVersion)
                                end)
                                updateAlertDlg.setButton2("Later", function()
                                    updateAlertDlg.dismiss()
                                end)
                                showSafe(updateAlertDlg)
                            end
                        })
                    end
                end)
            else
                checkAndShowNewFeatures()
            end
        end
    end)
end

function performUpdate(mainCode, onlineVersion)
    if not mainCode or trim(mainCode) == "" then
        showUpdateErrorDialog("Update Failed", "Main plugin code is empty.")
        return
    end
    updateInProgress = true
    local function updateProcess()
        local success = false
        local tempPath = PLUGIN_PATH .. ".temp_update"
        local f = io.open(tempPath, "w")
        if f then
            f:write(mainCode)
            f:close()
            local fileExists = io.open(PLUGIN_PATH, "r")
            if fileExists then
                fileExists:close()
                local delSuccess = pcall(function()
                    os.remove(PLUGIN_PATH)
                end)
                if delSuccess then
                    local renameSuccess = pcall(function()
                        os.rename(tempPath, PLUGIN_PATH)
                    end)
                    if renameSuccess then
                        success = true
                    end
                end
            else
                local renameSuccess = pcall(function()
                    os.rename(tempPath, PLUGIN_PATH)
                end)
                if renameSuccess then
                    success = true
                end
            end
            if not success then
                pcall(function() os.remove(tempPath) end)
            end
        end
        if success then
            updateInProgress = false
            Handler(Looper.getMainLooper()).post(Runnable{
                run=function()
                    beepAndVibrate()
                    
                    local successDialog = LuaDialog(ctx)
                    successDialog.setTitle("Update Successful")
                    successDialog.setMessage("Plugin successfully updated to version " .. onlineVersion .. ".\n\nPlugin will restart automatically.")
                    successDialog.setButton("OK", function()
                        successDialog.dismiss()
                        if mainDialogInstance then
                            mainDialogInstance.dismiss()
                        end
                        Handler(Looper.getMainLooper()).postDelayed(Runnable({
                            run = function()
                                prefs.edit().putString("lastShownVersion", "").apply()
                                local pluginFile = io.open(PLUGIN_PATH, "r")
                                if pluginFile then
                                    pluginFile:close()
                                    local func, err = loadfile(PLUGIN_PATH)
                                    if func then
                                        pcall(func)
                                    end
                                end
                            end
                        }), 2000)
                    end)
                    showSafe(successDialog)
                end
            })
            return
        else
            updateInProgress = false
            showUpdateErrorDialog("Update Failed", "Update failed. Please try again.")
        end
    end
    local updateThread = Thread(luajava.bindClass("java.lang.Runnable"){
        run = updateProcess
    })
    updateThread.start()
end
-- ===========================================

Thread(luajava.bindClass("java.lang.Runnable"){
    run = function()
        Thread.sleep(3000)
        checkUpdate()
    end
}).start()

local function formatSimple(ms)
local s = math.floor(ms / 1000)
local h = math.floor(s / 3600)
local m = math.floor((s % 3600) / 60)
local sec = s % 60
return string.format("%02d:%02d:%02d", h, m, sec)
end

local function formatDurationFriendly(ms)
local s = math.floor(ms / 1000)
local m = math.floor(s / 60)
local sec = s % 60
if m > 0 then
return string.format("%d minute(s) %d second(s)", m, sec)
else
return string.format("%d second(s)", sec)
end
end

local function formatSizeInt(bytes)
if bytes >= 1073741824 then return math.floor(bytes / 1073741824) .. " GB"
elseif bytes >= 1048576 then return math.floor(bytes / 1048576) .. " MB" end
return math.floor(bytes / 1024) .. " KB"
end

local function sanitizeName(name)
local n = tostring(name):gsub('[\\/:*?"<>|]', "_")
return n ~= "" and n or nil
end

local function stopVideoPreview()
is_video_previewing = false
is_playing = false
if videoPreviewPlayer then
pcall(function()
if videoPreviewPlayer.isPlaying() then videoPreviewPlayer.stop() end
videoPreviewPlayer.reset()
end)
end
if previewBtn then
setT(previewBtn, "PLAY PREVIEW")
end
end

local function pauseVideoPreview()
if videoPreviewPlayer and videoPreviewPlayer.isPlaying() then
videoPreviewPlayer.pause()
is_playing = false
if previewBtn then
setT(previewBtn, "PLAY PREVIEW")
end
speakTTS("Paused", 100)
end
end

local function resumeVideoPreview()
if videoPreviewPlayer and not videoPreviewPlayer.isPlaying() then
videoPreviewPlayer.start()
is_playing = true
if previewBtn then
setT(previewBtn, "PAUSE PREVIEW")
end
speakTTS("Resumed", 100)
end
end

local function updateSelectedVideoDisplay()
    if #selected_videos_list > 0 and selected_videos_list[current_video_index] then
        local current = selected_videos_list[current_video_index]
        selected_video_path = current.path
        selected_video_name = current.name
        selected_video_duration = current.duration
        selected_video_size = current.size
        
        if selectedVideoTitleTV then
            local displayText
            if #selected_videos_list == 1 then
                displayText = current.name .. "\n" .. formatSimple(current.duration) .. " | " .. formatSizeInt(current.size)
            else
                displayText = "(" .. current_video_index .. " of " .. #selected_videos_list .. ") " .. current.name .. "\n" .. formatSimple(current.duration) .. " | " .. formatSizeInt(current.size)
            end
            setT(selectedVideoTitleTV, displayText)
            selectedVideoTitleTV.setTextColor(0xFF000000)
        end
        
        if selectedVideoDurationTV then
            setT(selectedVideoDurationTV, "Duration: " .. formatDurationFriendly(current.duration))
        end
    else
        selected_video_path = nil
        selected_video_name = nil
        selected_video_duration = nil
        selected_video_size = nil
        if selectedVideoTitleTV then
            setT(selectedVideoTitleTV, "No video selected")
            selectedVideoTitleTV.setTextColor(0xFF666666)
        end
        if selectedVideoDurationTV then
            setT(selectedVideoDurationTV, "Duration: --")
        end
    end
end

local function playVideoPreview()
    if #selected_videos_list == 0 then
        speakTTS("No video selected", 0)
        return
    end

    if is_video_previewing and videoPreviewPlayer and videoPreviewPlayer.isPlaying() then
        pauseVideoPreview()
        return
    end

    if is_video_previewing and videoPreviewPlayer and not videoPreviewPlayer.isPlaying() then
        resumeVideoPreview()
        return
    end

    local currentVideo = selected_videos_list[current_video_index]
    if not currentVideo then
        speakTTS("No video available", 0)
        return
    end

    is_video_previewing = true
    speakTTS("Preview started", 100)

    videoPreviewPlayer = MediaPlayer()
    videoPreviewPlayer.setDataSource(currentVideo.path)

    videoPreviewPlayer.setOnPreparedListener(MediaPlayer.OnPreparedListener{
    onPrepared = function(mp)
        mp.start()
        is_playing = true
        if previewBtn then
            setT(previewBtn, "PAUSE PREVIEW")
        end
    end
    })

    videoPreviewPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
    onCompletion = function(mp)
        stopVideoPreview()
        speakTTS("Preview finished", 100)
    end
    })

    videoPreviewPlayer.setOnErrorListener(MediaPlayer.OnErrorListener{
    onError = function(mp, what, extra)
        stopVideoPreview()
        speakTTS("Preview error", 100)
        return true
    end
    })

    videoPreviewPlayer.prepareAsync()
end

local function playNextVideo()
    if #selected_videos_list == 0 then
        speakTTS("No videos selected", 0)
        return
    end
    
    if current_video_index < #selected_videos_list then
        stopVideoPreview()
        current_video_index = current_video_index + 1
        updateSelectedVideoDisplay()
        speakTTS("Video " .. current_video_index .. " of " .. #selected_videos_list .. ": " .. selected_videos_list[current_video_index].name, 100)
        giveFeedback(true)
    else
        speakTTS("This is the last video", 100)
        giveFeedback(false)
    end
end

local function playPrevVideo()
    if #selected_videos_list == 0 then
        speakTTS("No videos selected", 0)
        return
    end
    
    if current_video_index > 1 then
        stopVideoPreview()
        current_video_index = current_video_index - 1
        updateSelectedVideoDisplay()
        speakTTS("Video " .. current_video_index .. " of " .. #selected_videos_list .. ": " .. selected_videos_list[current_video_index].name, 100)
        giveFeedback(true)
    else
        speakTTS("This is the first video", 100)
        giveFeedback(false)
    end
end

local function extractAudioFromVideo(videoPath, customName, formatExtension)
local downloadDir = "/storage/emulated/0/Download/Video to Audio Converter by Tech For V I/"
local folder = File(downloadDir)
if not folder.exists() then folder.mkdirs() end

local cleanName = sanitizeName(customName) or ("Extracted_" .. SimpleDateFormat("yyyyMMdd_HHmmss").format(Date()))
local outPath = downloadDir .. cleanName .. "." .. formatExtension

local pd = ProgressDialog(service)
pd.setTitle("Video to Audio Converter")
pd.setMessage("Extracting audio track as " .. formatExtension:upper() .. "...")
pd.setCancelable(false)
pd.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
pd.show()

Thread(Runnable{
run = function()
local success = false
pcall(function()
local extractor = MediaExtractor()
extractor.setDataSource(videoPath)

local audioTrackIndex = -1
local audioFormat = nil

for i = 0, extractor.getTrackCount() - 1 do
local format = extractor.getTrackFormat(i)
local mime = format.getString(MediaFormat.KEY_MIME)
if mime and mime:find("audio/") then
audioTrackIndex = i
audioFormat = format
extractor.selectTrack(i)
break
end
end

if audioTrackIndex == -1 then
error("No audio track found in this video")
end

local muxerFormat = MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
local muxer = MediaMuxer(outPath, muxerFormat)
local writeTrackIndex = muxer.addTrack(audioFormat)
muxer.start()

local buffer = ByteBuffer.allocate(1024 * 1024)
local bufferInfo = MediaCodec.BufferInfo()

while true do
bufferInfo.size = extractor.readSampleData(buffer, 0)
if bufferInfo.size < 0 then break end

bufferInfo.presentationTimeUs = extractor.getSampleTime()
bufferInfo.flags = extractor.getSampleFlags()

muxer.writeSampleData(writeTrackIndex, buffer, bufferInfo)
extractor.advance()
end

muxer.stop()
muxer.release()
extractor.release()
success = true
end)

uiHandler.post(Runnable{
run = function()
pd.dismiss()
if success then
giveFeedback(true)
speakTTS("Audio extracted successfully as " .. cleanName .. "." .. formatExtension, 500)
else
giveFeedback(false)
speakTTS("Failed to extract audio from video", 500)
end
end
})
end
}).start()
end

local function extractAllSelectedVideos(formatExtension, namePrefix)
    if #selected_videos_list == 0 then
        speakTTS("No videos selected", 0)
        return
    end
    
    local total = #selected_videos_list
    local current = 0
    local failed = 0
    
    local function extractNext()
        current = current + 1
        if current > total then
            if failed > 0 then
                speakTTS("Completed with " .. failed .. " failures out of " .. total .. " videos", 500)
            else
                speakTTS("All " .. total .. " videos extracted successfully", 500)
            end
            return
        end
        
        local video = selected_videos_list[current]
        local customName = namePrefix .. "_" .. current .. "_" .. sanitizeName(video.name) or ("video_" .. current)
        
        local downloadDir = "/storage/emulated/0/Download/Video to Audio Converter by Tech For V I/"
        local folder = File(downloadDir)
        if not folder.exists() then folder.mkdirs() end
        
        local outPath = downloadDir .. customName .. "." .. formatExtension
        
        local pd = ProgressDialog(service)
        pd.setTitle("Video to Audio Converter")
        pd.setMessage("Extracting video " .. current .. " of " .. total .. "\n" .. video.name .. "\nFormat: " .. formatExtension:upper())
        pd.setCancelable(false)
        pd.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        pd.show()
        
        Thread(Runnable{
        run = function()
            local success = false
            pcall(function()
                local extractor = MediaExtractor()
                extractor.setDataSource(video.path)
                
                local audioTrackIndex = -1
                local audioFormat = nil
                
                for i = 0, extractor.getTrackCount() - 1 do
                    local format = extractor.getTrackFormat(i)
                    local mime = format.getString(MediaFormat.KEY_MIME)
                    if mime and mime:find("audio/") then
                        audioTrackIndex = i
                        audioFormat = format
                        extractor.selectTrack(i)
                        break
                    end
                end
                
                if audioTrackIndex == -1 then
                    error("No audio track found in this video")
                end
                
                local muxerFormat = MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
                local muxer = MediaMuxer(outPath, muxerFormat)
                local writeTrackIndex = muxer.addTrack(audioFormat)
                muxer.start()
                
                local buffer = ByteBuffer.allocate(1024 * 1024)
                local bufferInfo = MediaCodec.BufferInfo()
                
                while true do
                    bufferInfo.size = extractor.readSampleData(buffer, 0)
                    if bufferInfo.size < 0 then break end
                    
                    bufferInfo.presentationTimeUs = extractor.getSampleTime()
                    bufferInfo.flags = extractor.getSampleFlags()
                    
                    muxer.writeSampleData(writeTrackIndex, buffer, bufferInfo)
                    extractor.advance()
                end
                
                muxer.stop()
                muxer.release()
                extractor.release()
                success = true
            end)
            
            uiHandler.post(Runnable{
            run = function()
                pd.dismiss()
                if success then
                    speakTTS("Video " .. current .. " of " .. total .. " completed", 100)
                else
                    failed = failed + 1
                    speakTTS("Video " .. current .. " of " .. total .. " failed", 100)
                end
                extractNext()
            end
            })
        end
        }).start()
    end
    
    speakTTS("Starting extraction of " .. total .. " videos", 0)
    extractNext()
end

function showVideoSelectionDialog()
local videoData = {}
local proj = {MediaStore.Video.Media.DATA, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.DURATION, MediaStore.Video.Media.SIZE, MediaStore.Video.Media.DATE_MODIFIED}
local cursor = service.getContentResolver().query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, proj, nil, nil, nil)
if cursor then
while cursor.moveToNext() do 
table.insert(videoData, {
path = cursor.getString(0), 
name = cursor.getString(1), 
duration = cursor.getLong(2), 
size = cursor.getLong(3), 
date = cursor.getLong(4)
}) 
end
cursor.close()
end

local scrollView = ScrollView(service)
local mainL = LinearLayout(service)
mainL.setOrientation(1)
mainL.setPadding(40, 40, 40, 40)

local titleTV = TextView(service)
titleTV.setTextSize(22)
titleTV.setTypeface(nil, 1)
setT(titleTV, "Select Videos (Multiple)")
titleTV.setGravity(Gravity.CENTER)
titleTV.setTextColor(0xFF2196F3)
mainL.addView(titleTV)

local spacer1 = TextView(service)
setT(spacer1, "\n")
mainL.addView(spacer1)

local infoTV = TextView(service)
setT(infoTV, "Tap on any video to select/unselect it:")
infoTV.setTextSize(14)
mainL.addView(infoTV)

local spacer2 = TextView(service)
setT(spacer2, "\n")
mainL.addView(spacer2)

local search = EditText(service)
setH(search, "Search videos...")
search.setPadding(20, 15, 20, 15)
search.setBackgroundColor(0xFFF5F5F5)
mainL.addView(search)

local spacer3 = TextView(service)
setT(spacer3, "\n")
mainL.addView(spacer3)

local selectedCountTV = TextView(service)
selectedCountTV.setTextSize(14)
selectedCountTV.setGravity(Gravity.CENTER)
selectedCountTV.setPadding(10, 10, 10, 10)
selectedCountTV.setBackgroundColor(0xFFE3F2FD)
setT(selectedCountTV, "Selected: 0 videos")
mainL.addView(selectedCountTV)

local spacer4 = TextView(service)
setT(spacer4, "\n")
mainL.addView(spacer4)

local lv = ListView(service)

local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_multiple_choice)
lv.setChoiceMode(ListView.CHOICE_MODE_MULTIPLE)
local current_list = {}
local selected_positions = {}

local function refresh(q)
adapter.clear()
current_list = {}
local displayList = {}
for _, v in ipairs(videoData) do
if not q or v.name:lower():find(q:lower(), 1, true) then
table.insert(current_list, v)
table.insert(displayList, v.name .. "\n" .. formatSimple(v.duration) .. " | " .. formatSizeInt(v.size))
end
end
for i, item in ipairs(displayList) do
adapter.add(item)
end

for pos, _ in pairs(selected_positions) do
if pos <= adapter.getCount() then
lv.setItemChecked(pos - 1, true)
end
end

selectedCountTV.setText("Selected: " .. #selected_positions .. " videos")
end

refresh(nil)
lv.setAdapter(adapter)

search.addTextChangedListener(TextWatcher{
onTextChanged = function(s) 
refresh(tostring(s)) 
end
})

lv.setOnItemClickListener(function(parent, view, position, id)
local isChecked = lv.isItemChecked(position)
local actualPos = position + 1
local video = current_list[actualPos]

if video then
if isChecked then
selected_positions[actualPos] = video
else
selected_positions[actualPos] = nil
end
selectedCountTV.setText("Selected: " .. #selected_positions .. " videos")
speakTTS(isChecked and "Selected" or "Deselected", 100)
giveFeedback(true)
end
end)

local doneBtn = Button(service)
setT(doneBtn, "DONE - CONFIRM SELECTION")
doneBtn.setBackgroundColor(0xFF4CAF50)
doneBtn.setTextColor(0xFFFFFFFF)
doneBtn.setPadding(15, 20, 15, 20)
doneBtn.setTextSize(16)
doneBtn.setOnClickListener(function()
selected_videos_list = {}
for pos, video in pairs(selected_positions) do
table.insert(selected_videos_list, video)
end

if #selected_videos_list == 0 then
speakTTS("No videos selected", 0)
return
end

current_video_index = 1
updateSelectedVideoDisplay()

speakTTS(#selected_videos_list .. " videos selected", 100)
giveFeedback(true)

if selectDialogInstance then
selectDialogInstance.dismiss()
end

if mainDialogInstance then
mainDialogInstance.dismiss()
end

uiHandler.postDelayed(Runnable{
run = function()
if showMainDialog then
showMainDialog()
end
end
}, 100)
end)

mainL.addView(doneBtn)

local cancelBtn = Button(service)
setT(cancelBtn, "CANCEL")
cancelBtn.setBackgroundColor(0xFFF44336)
cancelBtn.setTextColor(0xFFFFFFFF)
cancelBtn.setPadding(15, 20, 15, 20)
cancelBtn.setTextSize(16)
cancelBtn.setOnClickListener(function()
if selectDialogInstance then selectDialogInstance.dismiss() end
end)

local btnSpacer = TextView(service)
setT(btnSpacer, "\n")
mainL.addView(btnSpacer)
mainL.addView(cancelBtn)

mainL.addView(lv)
scrollView.addView(mainL)

local builder = AlertDialog.Builder(service)
builder.setTitle("Select Videos")
builder.setView(scrollView)

selectDialogInstance = showSafe(builder)
end

function showAboutSupport()
    local help_dialog = LuaDialog(ctx)
    help_dialog.setTitle("Developer: Sabir Jamil")
    
    local help_layout = {
        LinearLayout, orientation = "vertical", padding = "16dp", layout_width = "fill", layout_height = "wrap",
        {
            TextView, text = "", textSize = "1sp", paddingBottom = "0dp"
        },
        {
            TextView, text = "Video to Audio Converter is a powerful tool that allows you to extract audio from any video file. Features include:\n\n• Select any video from your device storage\n• Preview video before extraction with play/pause controls\n• Extract audio in M4A (AAC in MP4 container) format\n• Extract audio in AAC (Raw AAC audio) format\n• Custom output file naming\n• Audio saved directly to Download/AudioEditor folder\n• Full accessibility support with TalkBack and haptic feedback\n\nSupported Formats: M4A, AAC - Extracts pure audio track from MP4, MKV, and other video formats.", textSize = "14sp", textColor = "#666666", paddingBottom = "15dp"
        },
        {
            TextView, text = "Join our community for more useful tools, feedback, and suggestions.", textSize = "14sp", textColor = "#000000", gravity = "center", paddingBottom = "15dp"
        },
        {
            ScrollView, layout_width = "fill", layout_height = "wrap",
            {
                LinearLayout, orientation = "vertical", layout_width = "fill", layout_height = "wrap", gravity = "center",
                {
                    Button, id = "sendFeedbackButton", text = "SEND FEEDBACK", layout_width = "fill", layout_height = "wrap", layout_margin = "2dp", textSize = "12sp", padding = "8dp", backgroundColor = "#FF9800", textColor = "#FFFFFF"
                },
                {
                    Button, id = "joinWhatsAppGroupButton", text = "JOIN WHATSAPP GROUP", layout_width = "fill", layout_height = "wrap", layout_margin = "2dp", textSize = "12sp", padding = "8dp", backgroundColor = "#25D366", textColor = "#FFFFFF"
                },
                {
                    Button, id = "joinYouTubeChannelButton", text = "JOIN YOUTUBE CHANNEL", layout_width = "fill", layout_height = "wrap", layout_margin = "2dp", textSize = "12sp", padding = "8dp", backgroundColor = "#FF0000", textColor = "#FFFFFF"
                },
                {
                    Button, id = "joinTelegramChannelButton", text = "JOIN TELEGRAM CHANNEL", layout_width = "fill", layout_height = "wrap", layout_margin = "2dp", textSize = "12sp", padding = "8dp", backgroundColor = "#2196F3", textColor = "#FFFFFF"
                },
                {
                    Button, id = "goBackButton", text = "GO BACK", layout_width = "fill", layout_height = "wrap", layout_margin = "2dp", textSize = "12sp", padding = "8dp", backgroundColor = "#9E9E9E", textColor = "#FFFFFF"
                }
            }
        }
    }
    
    local help_views = {}
    help_dialog.setView(loadlayout(help_layout, help_views))
    help_dialog.setCancelable(true)
    
    function showTextInputDialog(hint, callback)
        local inputLayout = LinearLayout(ctx)
        inputLayout.setOrientation(1)
        inputLayout.setPadding(40, 40, 40, 40)
        local title = TextView(ctx)
        title.setText(hint)
        title.setTextSize(16)
        title.setGravity(Gravity.CENTER)
        title.setPadding(0, 0, 0, 20)
        inputLayout.addView(title)
        local textBox = EditText(ctx)
        textBox.setHint("Type here...")
        textBox.setGravity(Gravity.TOP)
        textBox.setLayoutParams(LinearLayout.LayoutParams(-1, 200))
        inputLayout.addView(textBox)
        local btnLayout = LinearLayout(ctx)
        btnLayout.setOrientation(0)
        btnLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        local okBtn = Button(ctx)
        okBtn.setText("OK")
        okBtn.setBackgroundColor(0xFF2E7D32)
        okBtn.setTextColor(0xFFFFFFFF)
        local okParams = LinearLayout.LayoutParams(0, -2, 1)
        okParams.setMargins(0, 10, 5, 0)
        okBtn.setLayoutParams(okParams)
        btnLayout.addView(okBtn)
        local cancelBtn = Button(ctx)
        cancelBtn.setText("CANCEL")
        cancelBtn.setBackgroundColor(0xFF9E9E9E)
        cancelBtn.setTextColor(0xFFFFFFFF)
        local cancelParams = LinearLayout.LayoutParams(0, -2, 1)
        cancelParams.setMargins(5, 10, 0, 0)
        cancelBtn.setLayoutParams(cancelParams)
        btnLayout.addView(cancelBtn)
        inputLayout.addView(btnLayout)
        local inputDialog = LuaDialog(ctx)
        inputDialog.setTitle("Enter Text")
        inputDialog.setView(inputLayout)
        inputDialog.setCancelable(true)
        cancelBtn.onClick = function()
            inputDialog.dismiss()
        end
        okBtn.onClick = function()
            local text = textBox.getText().toString()
            inputDialog.dismiss()
            if text ~= "" then
                callback(text)
            end
        end
        showSafe(inputDialog)
    end
    
    function notify(msg)
        Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
    end
    
    help_views.sendFeedbackButton.onClick = function()
        local feedbackLayout = LinearLayout(ctx)
        feedbackLayout.setOrientation(1)
        feedbackLayout.setPadding(40, 40, 40, 40)
        local nameButton = Button(ctx)
        nameButton.setText("Enter Your Name")
        nameButton.setBackgroundColor(0xFF2196F3)
        nameButton.setTextColor(0xFFFFFFFF)
        nameButton.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        feedbackLayout.addView(nameButton)
        local whatsappButton = Button(ctx)
        whatsappButton.setText("WhatsApp Number (Optional)")
        whatsappButton.setBackgroundColor(0xFF2196F3)
        whatsappButton.setTextColor(0xFFFFFFFF)
        whatsappButton.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        feedbackLayout.addView(whatsappButton)
        local messageButton = Button(ctx)
        messageButton.setText("Write your feedback here...")
        messageButton.setBackgroundColor(0xFF2196F3)
        messageButton.setTextColor(0xFFFFFFFF)
        messageButton.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        feedbackLayout.addView(messageButton)
        local btnLayout = LinearLayout(ctx)
        btnLayout.setOrientation(0)
        btnLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        local sendBtn = Button(ctx)
        sendBtn.setText("SEND")
        sendBtn.setBackgroundColor(0xFF2E7D32)
        sendBtn.setTextColor(0xFFFFFFFF)
        local sendParams = LinearLayout.LayoutParams(0, -2, 1)
        sendParams.setMargins(0, 10, 5, 0)
        sendBtn.setLayoutParams(sendParams)
        btnLayout.addView(sendBtn)
        local backBtn = Button(ctx)
        backBtn.setText("GO BACK")
        backBtn.setBackgroundColor(0xFF9E9E9E)
        backBtn.setTextColor(0xFFFFFFFF)
        local backParams = LinearLayout.LayoutParams(0, -2, 1)
        backParams.setMargins(5, 10, 0, 0)
        backBtn.setLayoutParams(backParams)
        btnLayout.addView(backBtn)
        feedbackLayout.addView(btnLayout)
        local feedbackDialog = LuaDialog(ctx)
        feedbackDialog.setTitle("Send Feedback to Developer")
        feedbackDialog.setView(feedbackLayout)
        feedbackDialog.setCancelable(true)
        local nameText = ""
        local whatsappText = ""
        local messageText = ""
        nameButton.onClick = function()
            showTextInputDialog("Enter Your Name", function(text)
                nameText = text
                nameButton.setText("NAME: " .. text)
            end)
        end
        whatsappButton.onClick = function()
            showTextInputDialog("WhatsApp Number (Optional)", function(text)
                whatsappText = text
                whatsappButton.setText("WHATSAPP NUMBER: " .. text)
            end)
        end
        messageButton.onClick = function()
            showTextInputDialog("Write your feedback here...", function(text)
                messageText = text
                messageButton.setText("FEEDBACK: " .. text)
            end)
        end
        backBtn.onClick = function()
            feedbackDialog.dismiss()
        end
        sendBtn.onClick = function()
            if nameText == "" or messageText == "" then
                notify("Please enter name and message")
                speakTTS("Please enter name and message", 0)
                return
            end
            local appName = "Video to Audio Converter"
            local apiUrl = "https://telegram-bot-rouge-five.vercel.app/api/send"
            local fullData = "App Name: " .. appName .. "\nName: " .. nameText .. "\nWhatsApp Number: " .. whatsappText .. "\nFeedback: " .. messageText
            speakTTS("Sending feedback", 0)
            Http.post(apiUrl, {message = fullData}, function(code, body)
                Handler(Looper.getMainLooper()).post(Runnable({
                    run = function()
                        if code == 200 then
                            notify("Feedback sent successfully!")
                            speakTTS("Feedback sent successfully", 0)
                            feedbackDialog.dismiss()
                        else
                            notify("Failed to send feedback")
                            speakTTS("Failed to send feedback", 0)
                        end
                    end
                }))
            end)
        end
        showSafe(feedbackDialog)
    end
    
    help_views.joinWhatsAppGroupButton.onClick = function()
        speakTTS("Opening WhatsApp group", 0)
        local function performActions()
            help_dialog.dismiss()
            if mainDialogInstance then
                mainDialogInstance.dismiss()
            end
            uiHandler.postDelayed(Runnable{
                run = function()
                    local success, errorMsg = pcall(function()
                        local message = "Assalam%20o%20Alaikum.%20I%20hope%20you%20are%20doing%20well.%20I%20would%20like%20to%20join%20your%20WhatsApp%20group.%20Kindly%20share%20the%20instructions.%20group%20rules%20and%20regulations.%20Thank%20you.%20so%20much"
                        local url = "https://wa.me/923486623399?text=" .. message
                        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        ctx.startActivity(intent)
                    end)
                    if not success then
                        notify("Could not open WhatsApp")
                        speakTTS("Could not open WhatsApp", 0)
                    end
                end
            }, 500)
        end
        performActions()
    end
    
    help_views.joinYouTubeChannelButton.onClick = function()
        speakTTS("Opening YouTube channel", 0)
        local function performActions()
            help_dialog.dismiss()
            if mainDialogInstance then
                mainDialogInstance.dismiss()
            end
            uiHandler.postDelayed(Runnable{
                run = function()
                    local success, errorMsg = pcall(function()
                        local url = "https://www.youtube.com/@TechForVI"
                        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        ctx.startActivity(intent)
                    end)
                    if not success then
                        notify("Could not open YouTube")
                        speakTTS("Could not open YouTube", 0)
                    end
                end
            }, 500)
        end
        performActions()
    end
    
    help_views.joinTelegramChannelButton.onClick = function()
        speakTTS("Opening Telegram channel", 0)
        local function performActions()
            help_dialog.dismiss()
            if mainDialogInstance then
                mainDialogInstance.dismiss()
            end
            uiHandler.postDelayed(Runnable{
                run = function()
                    local success, errorMsg = pcall(function()
                        local url = "https://t.me/TechForVI"
                        local packageManager = ctx.getPackageManager()
                        local telegramIntent = packageManager.getLaunchIntentForPackage("org.telegram.messenger")
                        
                        if telegramIntent ~= nil then
                            local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.setPackage("org.telegram.messenger")
                            ctx.startActivity(intent)
                        else
                            local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            ctx.startActivity(intent)
                        end
                    end)
                    if not success then
                        notify("Could not open Telegram")
                        speakTTS("Could not open Telegram", 0)
                    end
                end
            }, 500)
        end
        performActions()
    end
    
    help_views.goBackButton.onClick = function()
        help_dialog.dismiss()
        speakTTS("Going back", 0)
    end
    
    help_dialog.setOnCancelListener{
        onCancel = function()
            help_dialog.dismiss()
        end
    }
    showSafe(help_dialog)
end

function showMainDialog()
local mainLayout = LinearLayout(service)
mainLayout.setOrientation(1)
mainLayout.setPadding(40, 40, 40, 40)

local headingTV = TextView(service)
headingTV.setTextSize(22)
headingTV.setTypeface(nil, 1)
setT(headingTV, "Video to Audio Converter")
headingTV.setGravity(Gravity.CENTER)
headingTV.setTextColor(0xFF2196F3)
mainLayout.addView(headingTV)

local spacer1 = TextView(service)
setT(spacer1, "\n")
mainLayout.addView(spacer1)

local btnSelectFile = Button(service)
setT(btnSelectFile, "SELECT VIDEO FILE")
btnSelectFile.setBackgroundColor(0xFFFF9800)
btnSelectFile.setTextColor(0xFFFFFFFF)
btnSelectFile.setPadding(15, 25, 15, 25)
btnSelectFile.setTextSize(16)
btnSelectFile.setOnClickListener(function()
if mainDialogInstance then
mainDialogInstance.dismiss()
end
showVideoSelectionDialog()
end)
mainLayout.addView(btnSelectFile)

local spacer2 = TextView(service)
setT(spacer2, "\n")
mainLayout.addView(spacer2)

selectedVideoTitleTV = TextView(service)
if #selected_videos_list > 0 then
    local current = selected_videos_list[current_video_index]
    if #selected_videos_list == 1 then
        setT(selectedVideoTitleTV, current.name .. "\n" .. formatSimple(current.duration) .. " | " .. formatSizeInt(current.size))
    else
        setT(selectedVideoTitleTV, "(" .. current_video_index .. " of " .. #selected_videos_list .. ") " .. current.name .. "\n" .. formatSimple(current.duration) .. " | " .. formatSizeInt(current.size))
    end
    selectedVideoTitleTV.setTextColor(0xFF000000)
else
    setT(selectedVideoTitleTV, "No video selected")
    selectedVideoTitleTV.setTextColor(0xFF666666)
end
selectedVideoTitleTV.setGravity(Gravity.CENTER)
selectedVideoTitleTV.setTextSize(14)
selectedVideoTitleTV.setPadding(10, 20, 10, 20)
selectedVideoTitleTV.setBackgroundColor(0xFFEEEEEE)
mainLayout.addView(selectedVideoTitleTV)

local spacer3 = TextView(service)
setT(spacer3, "\n")
mainLayout.addView(spacer3)

selectedVideoDurationTV = TextView(service)
if #selected_videos_list > 0 then
    local current = selected_videos_list[current_video_index]
    setT(selectedVideoDurationTV, "Duration: " .. formatDurationFriendly(current.duration))
else
    setT(selectedVideoDurationTV, "Duration: --")
end
selectedVideoDurationTV.setGravity(Gravity.CENTER)
selectedVideoDurationTV.setTextSize(14)
selectedVideoDurationTV.setTextColor(0xFF333333)
selectedVideoDurationTV.setPadding(10, 10, 10, 10)
mainLayout.addView(selectedVideoDurationTV)

local spacer4 = TextView(service)
setT(spacer4, "\n")
mainLayout.addView(spacer4)

local buttonLayout = LinearLayout(service)
buttonLayout.setOrientation(1)
buttonLayout.setGravity(Gravity.CENTER)

-- Navigation buttons row (Previous Video, PLAY PREVIEW, NEXT VIDEO)
local navLayout = LinearLayout(service)
navLayout.setOrientation(0)
navLayout.setGravity(Gravity.CENTER)

prevBtn = Button(service)
setT(prevBtn, "Previous Video")
prevBtn.setBackgroundColor(0xFF2196F3)
prevBtn.setTextColor(0xFFFFFFFF)
prevBtn.setPadding(15, 20, 15, 20)
prevBtn.setTextSize(14)
prevBtn.setOnClickListener(function()
    if #selected_videos_list == 0 then
        speakTTS("No videos selected", 0)
        return
    end
    playPrevVideo()
end)

previewBtn = Button(service)
setT(previewBtn, "PLAY PREVIEW")
previewBtn.setBackgroundColor(0xFF4CAF50)
previewBtn.setTextColor(0xFFFFFFFF)
previewBtn.setPadding(15, 25, 15, 25)
previewBtn.setTextSize(16)
previewBtn.setOnClickListener(function()
if #selected_videos_list == 0 then
speakTTS("Please select a video first", 0)
return
end
playVideoPreview()
end)

nextBtn = Button(service)
setT(nextBtn, "NEXT VIDEO")
nextBtn.setBackgroundColor(0xFF2196F3)
nextBtn.setTextColor(0xFFFFFFFF)
nextBtn.setPadding(15, 20, 15, 20)
nextBtn.setTextSize(14)
nextBtn.setOnClickListener(function()
    if #selected_videos_list == 0 then
        speakTTS("No videos selected", 0)
        return
    end
    playNextVideo()
end)

navLayout.addView(prevBtn)
local navSpacer = TextView(service)
setT(navSpacer, "  ")
navLayout.addView(navSpacer)
navLayout.addView(previewBtn)
local navSpacer2 = TextView(service)
setT(navSpacer2, "  ")
navLayout.addView(navSpacer2)
navLayout.addView(nextBtn)

buttonLayout.addView(navLayout)

local spacer5 = TextView(service)
setT(spacer5, "\n")
buttonLayout.addView(spacer5)

local extractBtn = Button(service)
setT(extractBtn, "EXTRACT AUDIO")
extractBtn.setBackgroundColor(0xFF2196F3)
extractBtn.setTextColor(0xFFFFFFFF)
extractBtn.setPadding(15, 25, 15, 25)
extractBtn.setTextSize(16)

extractBtn.setOnClickListener(function()
if #selected_videos_list == 0 then
speakTTS("Please select a video first", 0)
return
end

stopVideoPreview()

local formats = {"M4A (AAC in MP4 container)", "AAC (Raw AAC audio)"}
local formatBuilder = AlertDialog.Builder(service)
formatBuilder.setTitle("Select Output Format")
formatBuilder.setItems(formats, function(dialog, which)
local selectedFormat = (which == 0) and "m4a" or "aac"

if #selected_videos_list == 1 then
    local nameLayout = LinearLayout(service)
    nameLayout.setOrientation(1)
    nameLayout.setPadding(40, 40, 40, 40)

    local nameTV = TextView(service)
    setT(nameTV, "Output Audio Name (Optional):")
    nameTV.setTextSize(16)
    nameLayout.addView(nameTV)

    local spacerName = TextView(service)
    setT(spacerName, "\n")
    nameLayout.addView(spacerName)

    local nameEt = EditText(service)
    local defaultName = sanitizeName(selected_videos_list[1].name) or "extracted_audio"
    setH(nameEt, defaultName)
    nameEt.setText(defaultName)
    nameLayout.addView(nameEt)

    local nameBuilder = AlertDialog.Builder(service)
    nameBuilder.setTitle("Save as ." .. selectedFormat)
    nameBuilder.setView(nameLayout)
    nameBuilder.setPositiveButton("EXTRACT", function()
        extractAudioFromVideo(selected_videos_list[1].path, nameEt.getText().toString(), selectedFormat)
    end)
    nameBuilder.setNegativeButton("CANCEL", nil)
    showSafe(nameBuilder)
else
    local nameLayout = LinearLayout(service)
    nameLayout.setOrientation(1)
    nameLayout.setPadding(40, 40, 40, 40)

    local nameTV = TextView(service)
    setT(nameTV, "Base Name for All Audios:")
    nameTV.setTextSize(16)
    nameLayout.addView(nameTV)
    
    local infoTV = TextView(service)
    setT(infoTV, "Files will be saved as: BaseName_1, BaseName_2, etc.")
    infoTV.setTextSize(12)
    infoTV.setTextColor(0xFF666666)
    nameLayout.addView(infoTV)

    local spacerName = TextView(service)
    setT(spacerName, "\n")
    nameLayout.addView(spacerName)

    local nameEt = EditText(service)
    local defaultName = "extracted_audio"
    setH(nameEt, defaultName)
    nameEt.setText(defaultName)
    nameLayout.addView(nameEt)

    local nameBuilder = AlertDialog.Builder(service)
    nameBuilder.setTitle("Extract " .. #selected_videos_list .. " videos as ." .. selectedFormat)
    nameBuilder.setView(nameLayout)
    nameBuilder.setPositiveButton("EXTRACT ALL", function()
        extractAllSelectedVideos(selectedFormat, nameEt.getText().toString())
    end)
    nameBuilder.setNegativeButton("CANCEL", nil)
    showSafe(nameBuilder)
end
end)
showSafe(formatBuilder)
end)
buttonLayout.addView(extractBtn)

local spacer6 = TextView(service)
setT(spacer6, "\n")
buttonLayout.addView(spacer6)

local aboutSupportBtn = Button(service)
setT(aboutSupportBtn, "ABOUT & SUPPORT")
aboutSupportBtn.setBackgroundColor(0xFF9C27B0)
aboutSupportBtn.setTextColor(0xFFFFFFFF)
aboutSupportBtn.setPadding(15, 25, 15, 25)
aboutSupportBtn.setTextSize(16)

aboutSupportBtn.setOnClickListener(function()
showAboutSupport()
speakTTS("About and support", 100)
end)
buttonLayout.addView(aboutSupportBtn)

local spacer7 = TextView(service)
setT(spacer7, "\n")
buttonLayout.addView(spacer7)

local exitBtn = Button(service)
setT(exitBtn, "EXIT")
exitBtn.setBackgroundColor(0xFFF44336)
exitBtn.setTextColor(0xFFFFFFFF)
exitBtn.setPadding(15, 25, 15, 25)
exitBtn.setTextSize(16)

exitBtn.setOnClickListener(function()
stopVideoPreview()
if mainDialogInstance then
mainDialogInstance.dismiss()
end
end)
buttonLayout.addView(exitBtn)

mainLayout.addView(buttonLayout)

local builder = AlertDialog.Builder(service)
builder.setView(mainLayout)
builder.setCancelable(true)

mainDialogInstance = showSafe(builder)
end

showMainDialog()
return true